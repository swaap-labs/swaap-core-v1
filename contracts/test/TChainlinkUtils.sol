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
        address oracleAddress1,
        uint8 decimals1, // sum of the decimals of the token and its oracle
        address oracleAddress2,
        uint8 decimals2 // sum of the decimals of the token and its oracle
    ) public view returns (uint256) {

        Struct.LatestRound memory latestRound1 = ChainlinkUtils.getLatestRound(oracleAddress1);
        Struct.LatestRound memory latestRound2 = ChainlinkUtils.getLatestRound(oracleAddress2);

        return ChainlinkUtils.getMaxRelativePriceInLastBlock(
            latestRound1,
            decimals1,
            latestRound2,
            decimals2
        );
    }

}
