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

import "../ChainlinkUtils.sol";

library TChainlinkUtils {

    function getMaxRelativePriceInLastBlock(
        address oracleAddress_1,
        address oracleAddress_2
    ) public view returns (uint256) {

        (uint80 roundId_1, int256 price_1, , uint256 timestamp_1, ) = IAggregatorV3(oracleAddress_1).latestRoundData();
        (uint80 roundId_2, int256 price_2, , uint256 timestamp_2, ) = IAggregatorV3(oracleAddress_2).latestRoundData();

        return ChainlinkUtils.getMaxRelativePriceInLastBlock(
            oracleAddress_1,
            roundId_1,
            price_1,
            timestamp_1,
            oracleAddress_2,
            roundId_2,
            price_2,
            timestamp_2
        );
    }

}
