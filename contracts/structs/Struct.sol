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

contract Struct {

    struct TokenGlobal {
        TokenRecord info;
        LatestRound latestRound;
    }

    struct LatestRound {
        address oracle;
        uint80  roundId;
        uint256 price;
        uint256 timestamp;
    }

    struct OracleState {
        uint8   decimals;
        address oracle;
        uint256 price;
    }

    struct HistoricalPricesParameters {
        uint8   lookbackInRound;
        uint256 lookbackInSec;
        uint256 timestamp;
    }
    
    struct HistoricalPricesData {
        uint256   startIndex;
        uint256[] timestamps;
        uint256[] prices;
    }
    
    struct SwapResult {
        uint256 amount;
        uint256 spread;
        uint256 taxBaseIn;
    }

    struct PriceResult {
        uint256 spotPriceBefore;
        uint256 spotPriceAfter;
        uint256 priceIn;
        uint256 priceOut;
    }

    struct GBMEstimation {
        int256  mean;
        uint256 variance;
        bool    success;
    }

    struct TokenRecord {
        uint256 balance;
        uint256 weight;
    }

    struct SwapParameters {
        uint256 amount;
        uint256 fee;
        uint256 fallbackSpread;
    }

    struct JoinExitSwapParameters {
        uint256 amount;
        uint256 fee;
        uint256 fallbackSpread;
        uint256 poolSupply;
    }

    struct GBMParameters {
        uint256 z;
        uint256 horizon;
    }

}