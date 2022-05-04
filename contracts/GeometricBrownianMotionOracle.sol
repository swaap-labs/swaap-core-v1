// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity =0.8.12;

import "./Num.sol";
import "./Const.sol";
import "./LogExpMath.sol";
import "./ChainlinkUtils.sol";
import "./structs/Struct.sol";


/**
* @title Library in charge of historical prices statistics computations
* @author borelien
* @notice This library implements a method to retrieve the mean/variance of a given pair of assets, from Chainlink data
* @dev Because Chainlink data feeds' samplings are usually sparse and with varying time spacings, the estimation
* of mean / variance objects are only approximations.
*/
library GeometricBrownianMotionOracle {

    /**
    * @notice Gets asset-pair approximate historical return's mean and variance
    * @param oracleIn The address of tokenIn's oracle
    * @param oracleOut The address of tokenOut's oracle
    * @param hpParameters The parameters for historical prices retrieval
    * @return gbmEstimation The asset-pair historical return's mean and variance
    */
    function getParametersEstimation(
        address oracleIn,
        address oracleOut,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    external view returns (Struct.GBMEstimation memory gbmEstimation) {
        Struct.LatestRound memory latestRoundIn = ChainlinkUtils.getLatestRound(oracleIn);
        Struct.LatestRound memory latestRoundOut = ChainlinkUtils.getLatestRound(oracleOut);
        return (
            getParametersEstimation(
                latestRoundIn,
                latestRoundOut,
                hpParameters
            )
        );
    }

    /**
    * @notice Gets asset-pair approximate historical return's mean and variance
    * @param latestRoundIn The round-to-start-from's data including its ID of tokenIn
    * @param latestRoundOut The round-to-start-from's data including its ID of tokenOut
    * @param hpParameters The parameters for historical prices retrieval
    * @return gbmEstimation The asset-pair historical return's mean and variance
    */
    function getParametersEstimation(
        Struct.LatestRound memory latestRoundIn,
        Struct.LatestRound memory latestRoundOut,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    internal view returns (Struct.GBMEstimation memory gbmEstimation) {

        // retrieve historical prices of tokenIn
        (uint256[] memory pricesIn, uint256[] memory timestampsIn, uint256 startIndexIn, bool noMoreDataPointIn) = getHistoricalPrices(
            latestRoundIn, hpParameters
        );
        if (!noMoreDataPointIn && startIndexIn < hpParameters.lookbackInRound) {
            return Struct.GBMEstimation(0, 0, false);
        }

        uint256 reducedLookbackInSecCandidate = hpParameters.timestamp - timestampsIn[startIndexIn];
        if (reducedLookbackInSecCandidate < hpParameters.lookbackInSec) {
            hpParameters.lookbackInSec = reducedLookbackInSecCandidate;
        }

        // retrieve historical prices of tokenOut
        (uint256[] memory pricesOut, uint256[] memory timestampsOut, uint256 startIndexOut, bool noMoreDataPointOut) = getHistoricalPrices(
            latestRoundOut, hpParameters
        );
        if (!noMoreDataPointOut && startIndexOut < hpParameters.lookbackInRound) {
            return Struct.GBMEstimation(0, 0, false);
        }

        return _getParametersEstimation(
            noMoreDataPointIn && noMoreDataPointOut,
            Struct.HistoricalPricesData(startIndexIn, timestampsIn, pricesIn),
            Struct.HistoricalPricesData(startIndexOut, timestampsOut, pricesOut),
            hpParameters
        );
    }

    /**
    * @notice Gets asset-pair historical data return's mean and variance
    * @param noMoreDataPoints True if and only if the retrieved data span over the whole time window of interest
    * @param hpDataIn Historical prices data of tokenIn
    * @param hpDataOut Historical prices data of tokenOut
    * @param hpParameters The parameters for historical prices retrieval
    * @return gbmEstimation The asset-pair historical return's mean and variance
    */
    function _getParametersEstimation(
        bool noMoreDataPoints,
        Struct.HistoricalPricesData memory hpDataIn,
        Struct.HistoricalPricesData memory hpDataOut,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    internal pure returns (Struct.GBMEstimation memory gbmEstimation) {

        // no price return can be calculated with only 1 data point
        if (hpDataIn.startIndex == 0 && hpDataOut.startIndex == 0) {
            return gbmEstimation = Struct.GBMEstimation(0, 0, true);
        }

        if (noMoreDataPoints) {
            uint256 ts = hpParameters.timestamp - hpParameters.lookbackInSec;
            hpDataIn.timestamps[hpDataIn.startIndex] = ts;
            hpDataOut.timestamps[hpDataOut.startIndex] = ts;
        } else {
            consolidateStartIndices(
                hpDataIn,
                hpDataOut
            );
            // no price return can be calculated with only 1 data point
            if (hpDataIn.startIndex == 0 && hpDataOut.startIndex == 0) {
                return gbmEstimation = Struct.GBMEstimation(0, 0, true);
            }
        }
        (int256[] memory values, uint256[] memory timestamps) = getSeries(
            hpDataIn.prices, hpDataIn.timestamps, hpDataIn.startIndex,
            hpDataOut.prices, hpDataOut.timestamps, hpDataOut.startIndex
        );
        (int256 mean, uint256 variance) = getStatistics(values, timestamps);

        return gbmEstimation = Struct.GBMEstimation(mean, variance, true);

    }

    /**
    * @notice Gets asset-pair historical prices with timestamps
    * @param pricesIn The historical prices of tokenIn
    * @param timestampsIn The timestamps corresponding to the tokenIn's historical prices
    * @param startIndexIn The tokenIn historical data's last valid index
    * @param pricesOut The tokenIn historical data's last valid index
    * @param timestampsOut The timestamps corresponding to the tokenOut's historical prices
    * @param startIndexOut The tokenOut historical data's last valid index
    * @return values The asset-pair historical prices array
    * @return timestamps The asset-pair historical timestamps array
    */
    function getSeries(
        uint256[] memory pricesIn, uint256[] memory timestampsIn, uint256 startIndexIn,
        uint256[] memory pricesOut, uint256[] memory timestampsOut, uint256 startIndexOut
    ) internal pure returns (int256[] memory values, uint256[] memory timestamps) {

        // compute the number of returns
        uint256 count = 1;
        {
            uint256 _startIndexIn = startIndexIn;
            uint256 _startIndexOut = startIndexOut;
            bool skip = true;
            while (_startIndexIn > 0 || _startIndexOut > 0) {
                (skip, _startIndexIn, _startIndexOut) = getNextSample(
                    _startIndexIn, _startIndexOut, timestampsIn, timestampsOut
                );
                if (!skip) {
                    count += 1;
                }
            }
            values = new int256[](count);
            timestamps = new uint256[](count);
            values[0] = int256(Num.bdiv(pricesOut[startIndexOut], pricesIn[startIndexIn]));
            timestamps[0] = Num.max(timestampsOut[startIndexOut], timestampsIn[startIndexIn]) * Const.BONE;
        }

        // compute actual returns
        {
            count = 1;
            bool skip = true;
            while (startIndexIn > 0 || startIndexOut > 0) {
                (skip, startIndexIn, startIndexOut) = getNextSample(
                    startIndexIn, startIndexOut, timestampsIn, timestampsOut
                );
                if (!skip) {
                    values[count] = int256(Num.bdiv(pricesOut[startIndexOut], pricesIn[startIndexIn]));
                    timestamps[count] = Num.max(timestampsOut[startIndexOut], timestampsIn[startIndexIn]) * Const.BONE;
                    count += 1;
                }
            }
        }

        return (values, timestamps);

    }

    /**
    * @notice Gets asset-pair historical mean/variance from timestamped data
    * @param values The historical values
    * @param timestamps The corresponding time deltas, in seconds
    * @return The asset-pair historical return's mean
    * @return The asset-pair historical return's variance
    */
    function getStatistics(int256[] memory values, uint256[] memory timestamps)
    internal pure returns (int256, uint256) {

        uint256 n = values.length;
        if (n < 2) {
            return (0, 0);
        }
        n -= 1;

        uint256 tWithPrecision = timestamps[n] - timestamps[0];

        // mean
        int256 mean = Num.bdivInt256(LogExpMath.ln(Num.bdivInt256(values[n], values[0])), int256(tWithPrecision));
        uint256 meanSquare;
        if (mean < 0) {
            meanSquare = Num.bmul(uint256(-mean), uint256(-mean));
        } else {
            meanSquare = Num.bmul(uint256(mean), uint256(mean));
        }
        // variance
        int256 variance = -int256(Num.bmul(meanSquare, tWithPrecision));
        for (uint256 i = 1; i <= n; i++) {
            int256 d = LogExpMath.ln(Num.bdivInt256(values[i], values[i - 1]));
            if (d < 0) {
                d = -d;
            }
            uint256 dAbs = uint256(d);
            variance += int256(Num.bdiv(Num.bmul(dAbs, dAbs), timestamps[i] - timestamps[i - 1]));
        }
        variance = Num.bdivInt256(variance, int256(n * Const.BONE));

        return (mean, uint256(Num.positivePart(variance)));
    }

    /**
    * @notice Finds the next data point in chronological order
    * @dev Few considerations:
    * - data point with same timestamp as previous point are tagged with a 'skip=true'
    * - when we reach the last point of a token, we consider it's value constant going forward with the other token
    * As a result the variance of those returns will be underestimated.
    * @param startIndexIn The tokenIn historical data's last valid index
    * @param startIndexOut The tokenOut historical data's last valid index
    * @param timestampsIn The timestamps corresponding to the tokenIn's historical prices
    * @param timestampsOut The timestamps corresponding to the tokenOut's historical prices
    * @return The 'skip' tag
    * @return The updated startIndexIn
    * @return The updated startIndexOut
    */
    function getNextSample(
        uint256 startIndexIn, uint256 startIndexOut,
        uint256[] memory timestampsIn, uint256[] memory timestampsOut
    ) internal pure returns (bool, uint256, uint256) {
        bool skip = true;
        uint256 nextStartIndexIn = startIndexIn > 0 ? startIndexIn - 1 : startIndexIn;
        uint256 nextStartIndexOut = startIndexOut > 0 ? startIndexOut - 1 : startIndexOut;
        if (timestampsIn[nextStartIndexIn] == timestampsOut[nextStartIndexOut]) {
            if ((timestampsIn[nextStartIndexIn] != timestampsIn[startIndexIn]) && (timestampsOut[nextStartIndexOut] != timestampsOut[startIndexOut])) {
                skip = false;
            }
            if (startIndexIn > 0) {
                startIndexIn--;
            }
            if (startIndexOut > 0) {
                startIndexOut--;
            }
        } else {
            if (startIndexOut == 0) {
                if (timestampsIn[nextStartIndexIn] != timestampsIn[startIndexIn]) {
                    skip = false;
                }
                if (startIndexIn > 0) {
                    startIndexIn--;
                }
            } else if (startIndexIn == 0) {
                if (timestampsOut[nextStartIndexOut] != timestampsOut[startIndexOut]) {
                    skip = false;
                }
                if (startIndexOut > 0) {
                    startIndexOut--;
                }
            } else {
                if (timestampsIn[nextStartIndexIn] < timestampsOut[nextStartIndexOut]) {
                    if (timestampsIn[nextStartIndexIn] != timestampsIn[startIndexIn]) {
                        skip = false;
                    }
                    if (startIndexIn > 0) {
                        startIndexIn--;
                    }
                } else {
                    if (timestampsOut[nextStartIndexOut] != timestampsOut[startIndexOut]) {
                        skip = false;
                    }
                    if (startIndexOut > 0) {
                        startIndexOut--;
                    }
                }
            }
        }
        return  (skip, startIndexIn, startIndexOut);
    }

    /**
    * @notice Gets historical prices from a Chainlink data feed
    * @dev Few specificities:
    * - it filters out round data with null price or timestamp
    * - it stops filling the prices/timestamps when:
    * a) hpParameters.lookbackInRound rounds have already been found
    * b) time window induced by hpParameters.lookbackInSec is no more satisfied
    * @param latestRound The round-to-start-from's data including its ID
    * @param hpParameters The parameters for historical prices retrieval
    * @return The historical prices
    * @return The historical timestamps
    * @return The last valid value index
    * @return True if the reported historical prices reaches the lookback time limit
    */
    function getHistoricalPrices(
        Struct.LatestRound memory latestRound,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    internal view returns (uint256[] memory, uint256[] memory, uint256, bool)
    {
        uint256 latestTimestamp = latestRound.timestamp;

        // historical price endtimestamp >= lookback window or it reverts
        uint256 timeLimit = hpParameters.timestamp - hpParameters.lookbackInSec;

        // result variables
        uint256[] memory prices = new uint256[](hpParameters.lookbackInRound);
        uint256[] memory timestamps = new uint256[](hpParameters.lookbackInRound);
        uint256 idx = 1;

        {

            prices[0] = uint256(latestRound.price); // is supposed to be well valid
            timestamps[0] = latestTimestamp; // is supposed to be well valid

            if (latestTimestamp < timeLimit) {
                return (prices, timestamps, 0, true);
            }

            uint80 count = 1;

            // buffer variables
            uint80 _roundId = latestRound.roundId;

            while ((_roundId > 0) && (count < hpParameters.lookbackInRound)) {

                _roundId--;
                (int256 _price, uint256 _timestamp) = ChainlinkUtils.getRoundData(latestRound.oracle, _roundId);

                if (_price > 0 && _timestamp > 0) {

                    prices[idx] = uint256(_price);
                    timestamps[idx] = _timestamp;
                    idx += 1;

                    if (_timestamp < timeLimit) {
                        return (prices, timestamps, idx - 1, true);
                    }

                }

                count += 1;

            }

        }

        return (prices, timestamps, idx - 1, false);
    }

    /**
    * @notice Consolidate the last valid indexes of tokenIn and tokenOut
    * @param hpDataIn Historical prices data of tokenIn
    * @param hpDataOut Historical prices data of tokenOut
    */
    function consolidateStartIndices(
        Struct.HistoricalPricesData memory hpDataIn,
        Struct.HistoricalPricesData memory hpDataOut
    )
    internal pure
    {

        // trim prices/timestamps by adjusting startIndexes
        if (hpDataIn.timestamps[hpDataIn.startIndex] > hpDataOut.timestamps[hpDataOut.startIndex]) {
            while ((hpDataOut.startIndex > 0) && (hpDataOut.timestamps[hpDataOut.startIndex - 1] <= hpDataIn.timestamps[hpDataIn.startIndex])) {
                --hpDataOut.startIndex;
            }
        } else if (hpDataIn.timestamps[hpDataIn.startIndex] < hpDataOut.timestamps[hpDataOut.startIndex]) {
            while ((hpDataIn.startIndex > 0) && (hpDataIn.timestamps[hpDataIn.startIndex - 1] <= hpDataOut.timestamps[hpDataOut.startIndex])) {
                --hpDataIn.startIndex;
            }
        }

    }

}