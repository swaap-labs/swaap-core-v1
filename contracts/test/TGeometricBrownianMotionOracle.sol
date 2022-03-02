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


import "../structs/Struct.sol";
import "../GeometricBrownianMotionOracle.sol";


library TGeometricBrownianMotionOracle {

    function getParametersEstimation(
        address oracleIn, uint80 roundIdIn, int256 priceIn, uint256 timestampIn,
        address oracleOut, uint80 roundIdOut, int256 priceOut, uint256 timestampOut,
        uint8 priceStatisticsLookbackInRound, uint256 priceStatisticsLookbackInSec,
        uint256 timestamp
    ) public view returns (Struct.GBMEstimation memory results) {

        Struct.LatestRound memory inputIn = Struct.LatestRound(
            oracleIn,
            roundIdIn, priceIn, timestampIn
        );
        Struct.LatestRound memory inputOut = Struct.LatestRound(
            oracleOut,
            roundIdOut, priceOut, timestampOut
        );
        Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
            priceStatisticsLookbackInRound,
            priceStatisticsLookbackInSec,
            timestamp
        );

        return results = GeometricBrownianMotionOracle.getParametersEstimation(
            inputIn, inputOut, hpParameters
        );
    }

    function getPairReturns (
        uint256[] memory pricesIn, uint256[] memory timestampsIn, uint256 startIndexIn,
        uint256[] memory pricesOut, uint256[] memory timestampsOut, uint256 startIndexOut
    ) public pure returns (int256[] memory) {
        return GeometricBrownianMotionOracle.getPairReturns(
            pricesIn, timestampsIn, startIndexIn,
            pricesOut, timestampsOut, startIndexOut
        );
    }

    function getStatistics(int256[] memory periodsReturn, uint256 actualTimeWindowInSec)
    public pure returns (int256, uint256) {
        return GeometricBrownianMotionOracle.getStatistics(periodsReturn, actualTimeWindowInSec);
    }

}