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

pragma solidity =0.8.0;

import "./interfaces/IAggregatorV3.sol";
import "./Num.sol";
import "./Const.sol";
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
    * @notice Gets asset-pair approximate historical returns mean and variance
    * @dev Because of Chainlink sparse sampling, a lot of tradeoffs have been made.
    * @param inputIn The round-to-start-from's data including its ID of tokenIn
    * @param inputOut The round-to-start-from's data including its ID of tokenOut
    * @param hpParameters The parameters for historical prices retrieval
    * @return gbmEstimation The asset-pair historical returns mean and variance
    */
    function getParametersEstimation(
        Struct.LatestRound memory inputIn, Struct.LatestRound memory inputOut,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    internal view returns (Struct.GBMEstimation memory gbmEstimation) {

        uint256 endTimestamp = hpParameters.timestamp;

        // retrieve historical prices of tokenIn
        (uint256[] memory pricesIn, uint256[] memory timestampsIn, uint256 startIndexIn, bool noMoreDataPointIn) = getHistoricalPrices(
            inputIn, hpParameters, endTimestamp
        );
        {
            uint256 reducedLookbackInSecCandidate = endTimestamp - timestampsIn[startIndexIn];
            if (reducedLookbackInSecCandidate < hpParameters.lookbackInSec) {
                hpParameters.lookbackInSec = reducedLookbackInSecCandidate;
            }
        }
        // retrieve historical prices of tokenOut
        (uint256[] memory pricesOut, uint256[] memory timestampsOut, uint256 startIndexOut, bool noMoreDataPointOut) = getHistoricalPrices(
            inputOut, hpParameters, endTimestamp
        );

        // no price return can be calculated with only 1 data point
        if (startIndexIn == 0 && startIndexOut == 0) {
            return gbmEstimation = Struct.GBMEstimation(0, 0);
        }

        uint256 actualTimeWindowInSec;
        if (noMoreDataPointIn && noMoreDataPointOut) {
            // considering the full lookback time window
            actualTimeWindowInSec = hpParameters.lookbackInSec;
        } else {
            uint256 startTimestamp = timestampsOut[startIndexOut];
            // trim prices/timestamps by adjusting startIndexes
            if (timestampsIn[startIndexIn] > timestampsOut[startIndexOut]) {
                startTimestamp = timestampsIn[startIndexIn];
                while ((startIndexOut > 0) && (timestampsOut[startIndexOut - 1] <= startTimestamp)) {
                    startIndexOut--;
                }
            } else {
                startTimestamp = timestampsOut[startIndexOut];
                while ((startIndexIn > 0) && (timestampsIn[startIndexIn - 1] <= startTimestamp)) {
                    startIndexIn--;
                }
            }

            // no price return can be calculated with only 1 data point
            if (startIndexIn == 0 && startIndexOut == 0) {
                return gbmEstimation = Struct.GBMEstimation(0, 0);
            }

            actualTimeWindowInSec = endTimestamp - startTimestamp; // will always be < than lookbackInSec

        }

        if (actualTimeWindowInSec > 1) {
            (int256 mean, uint256 variance) = getStatistics(
                // compute returns
                getPairReturns(
                    pricesIn, timestampsIn, startIndexIn,
                    pricesOut, timestampsOut, startIndexOut
                ),
                actualTimeWindowInSec
            );
            return gbmEstimation = Struct.GBMEstimation(mean, variance);
        }

        return gbmEstimation = Struct.GBMEstimation(0, 0);

    }

    /**
    * @notice Gets asset-pair historical percentage returns from timestamped data
    * @dev Few considerations:
    * - we compute the number of percentage returns first
    * - when the first startIndex reaches 0 we consider the price of the corresponding token to be constant
    * - we compute returns until both startIndexes reach 0
    * Because of Chainlink sparse sampling, we are only able to compute an approximation of the true returns:
    * - we consider the asset-pair price constant until a new price is fired
    * - we compute percentage returns as such: (price_t+1 - price_t) / price_t
    * - the time steps (t) are expressed in seconds
    * @param pricesIn The historical prices of tokenIn
    * @param timestampsIn The timestamps corresponding to the tokenIn's historical prices
    * @param startIndexIn The historical prices of tokenOut
    * @param pricesOut The tokenIn historical data's last valid index
    * @param timestampsOut The timestamps corresponding to the tokenOut's historical prices
    * @param startIndexOut The tokenOut historical data's last valid index
    * @return periodsReturn The asset-pair historical returns array
    */
    function getPairReturns(
        uint256[] memory pricesIn, uint256[] memory timestampsIn, uint256 startIndexIn,
        uint256[] memory pricesOut, uint256[] memory timestampsOut, uint256 startIndexOut
    ) internal pure returns (int256[] memory periodsReturn) {

        // compute the number of returns
        uint256 count;
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
            periodsReturn = new int256[](count);
        }

        // compute actual returns
        {
            int256 currentPrice = int256(Num.bdiv(pricesOut[startIndexOut], pricesIn[startIndexIn]));
            count = 1;
            bool skip = true;
            while (startIndexIn > 0 || startIndexOut > 0) {
                (skip, startIndexIn, startIndexOut) = getNextSample(
                    startIndexIn, startIndexOut, timestampsIn, timestampsOut
                );
                if (!skip) {
                    int256 futurePrice = int256(Num.bdiv(pricesOut[startIndexOut], pricesIn[startIndexIn]));
                    periodsReturn[count - 1] = Num.bdivInt256(futurePrice - currentPrice, currentPrice);
                    currentPrice = futurePrice;
                    count += 1;
                }
            }
        }

        return (periodsReturn);

    }

    /**
    * @notice Gets asset-pair historical mean/variance from timestamped data
    * @dev Because of Chainlink sparse sampling, we are only able to compute an approximation of the returns:
    * - we consider the asset-pair price constant until a new price is fired
    * - the returns consist in (price_t+1 - price_t) / price_t values
    * - the time steps (t) are expressed in seconds
    * As a result the variance of those returns will be underestimated.
    * @param periodsReturn The historical percentage returns
    * @param actualTimeWindowInSec The time windows in seconds
    * @return The asset-pair historical returns mean
    * @return The asset-pair historical returns variance
    */
    function getStatistics(int256[] memory periodsReturn, uint256 actualTimeWindowInSec)
    internal pure returns (int256, uint256) {

        uint256 n = periodsReturn.length;
        if (actualTimeWindowInSec == 0) {
            return (0, 0);
        }

        uint256 actualTimeWindowInSecWithPrecision = Const.BONE * actualTimeWindowInSec;

        // mean
        int256 mean;
        for (uint256 i; i < n; i++) {
            mean += periodsReturn[i];
        }
        mean = Num.bdivInt256(mean, int256(actualTimeWindowInSecWithPrecision));

        // variance
        uint256 variance;
        if (mean > 0) {
            variance = Num.bmul(Num.bmul(actualTimeWindowInSecWithPrecision - n * Const.BONE, uint256(mean)), uint256(mean));
        } else if (mean < 0) {
            variance = Num.bmul(Num.bmul(actualTimeWindowInSecWithPrecision - n * Const.BONE, uint256(-mean)), uint256(-mean));
        }
        for (uint256 i; i < n; i++) {
            int256 d = periodsReturn[i] - mean;
            if (d < 0) {
                d = -d;
            }
            uint256 dAbs = uint256(d);
            variance += Num.bmul(dAbs, dAbs);
        }
        variance = Num.bdiv(variance, actualTimeWindowInSecWithPrecision - Const.BONE);

        return (mean, variance);
    }

    /**
    * @notice Finds the next data point in chronological order
    * @dev Few considerations:
    * - data point with same timestamp as previous point are tagged with a 'skip=true'
    * - when we reach the last point of a token, we consider it's value constant going forward with the other token
    * - we exit when both tokens
    * As a result the variance of those returns will be underestimated.
    * @param startIndexIn The historical prices of tokenOut
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
    * - if the returned index = hpParameters.lookbackInRound it means "no historical data was found"
    * - if stops filling the prices/timestamps when:
    * a) round data are 0 or when
    * b) hpParameters.lookbackInRound rounds have already been found
    * c) time window induced by hpParameters.lookbackInRound is no more satisfied
    * @param input The round-to-start-from's data including its ID
    * @param hpParameters The parameters for historical prices retrieval
    * @return The historical prices
    * @return The historical timestamps
    * @return The last valid value index
    */
    function getHistoricalPrices(
        Struct.LatestRound memory input,
        Struct.HistoricalPricesParameters memory hpParameters,
        uint256 endTimestamp
    )
    internal view returns (uint256[] memory, uint256[] memory, uint256, bool)
    {

        IAggregatorV3 priceFeed = IAggregatorV3(input.oracle);

        uint80 latestRoundId = input.roundId;
        int256 latestPrice = input.price;
        uint256 latestTimestamp = input.timestamp;

        uint256 timeLimit = 1;
        if (endTimestamp >= hpParameters.lookbackInSec) {
            timeLimit = endTimestamp - hpParameters.lookbackInSec;
        }

        // result variables
        uint256[] memory prices = new uint256[](hpParameters.lookbackInRound);
        uint256[] memory timestamps = new uint256[](hpParameters.lookbackInRound);
        uint256 idx = hpParameters.lookbackInRound + 1; // will mean 'empty arrays' in the following

        {

            prices[0] = uint256(latestPrice); // is supposed to be well valid
            timestamps[0] = latestTimestamp; // is supposed to be well valid

            if (latestTimestamp < timeLimit) {
                return (prices, timestamps, 0, true);
            }

            idx = 1;
            uint80 count = 1;

            // buffer variables
            uint80 _roundId = latestRoundId;

            while ((_roundId > 0) && (count < hpParameters.lookbackInRound)) {

                _roundId--;
                (int256 _price, uint256 _timestamp) = getRoundData(priceFeed, _roundId);

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
    * @notice Retrieves historical data from round id.
    * @dev Will not fail and return (0, 0) if no data can be found.
    * @param priceFeed The oracle of interest
    * @param _roundId The the round of interest ID
    * @return The round price
    * @return The round timestamp
    */
    function getRoundData(IAggregatorV3 priceFeed, uint80 _roundId) internal view returns (int256, uint256) {
        (, int256 _price, , uint256 _timestamp, ) = priceFeed.getRoundData(_roundId);
        return (_price, _timestamp);
    }

}