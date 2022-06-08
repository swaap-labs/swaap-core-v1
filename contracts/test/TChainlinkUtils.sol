// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.

// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.

pragma solidity =0.8.12;

import "../ChainlinkUtils.sol";

library TChainlinkUtils {

    function getMaxRelativePriceInLastBlock(
        address oracleAddress_1,
        uint8 decimals_1, // sum of the decimals of the token and its oracle
        address oracleAddress_2,
        uint8 decimals_2 // sum of the decimals of the token and its oracle
    ) public view returns (uint256) {

        Struct.LatestRound memory latestRound_1 = ChainlinkUtils.getLatestRound(oracleAddress_1);
        Struct.LatestRound memory latestRound_2 = ChainlinkUtils.getLatestRound(oracleAddress_2);

        return ChainlinkUtils.getMaxRelativePriceInLastBlock(
            latestRound_1,
            decimals_1,
            latestRound_2,
            decimals_2
        );
    }

}
