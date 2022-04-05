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

library Const {
    uint256 public constant BONE                  = 10**18;

    uint256 public constant MIN_BOUND_TOKENS      = 2;
    uint256 public constant MAX_BOUND_TOKENS      = 8;

    uint256 public constant MIN_FEE               = BONE / 10**6;
    uint256 public constant BASE_FEE              = 25 * BONE / 10**5;
    uint256 public constant MAX_FEE               = BONE / 10;
    uint256 public constant EXIT_FEE              = 0;

    uint80 public constant MIN_WEIGHT             = uint80(BONE);
    uint80 public constant MAX_WEIGHT             = uint80(BONE * 50);
    uint80 public constant MAX_TOTAL_WEIGHT       = uint80(BONE * 50);
    uint256 public constant MIN_BALANCE           = BONE / 10**12;

    uint256 public constant INIT_POOL_SUPPLY      = BONE * 100;

    uint256 public constant MIN_BPOW_BASE         = 1 wei;
    uint256 public constant MAX_BPOW_BASE         = (2 * BONE) - 1 wei;
    uint256 public constant BPOW_PRECISION        = BONE / 10**10;

    uint256 public constant MAX_IN_RATIO          = BONE / 2;
    uint256 public constant MAX_OUT_RATIO         = (BONE / 3) + 1 wei;

    uint64 public constant BASE_Z                 = uint64(6 * BONE / 10);
    uint64 public constant MAX_Z                  = uint64(4 * BONE);

    uint256 public constant MIN_HORIZON           = 1 * BONE;
    uint256 public constant BASE_HORIZON          = 300 * BONE;
    uint256 public constant MAX_HORIZON           = 86400 * BONE;

    uint8 public constant MIN_LOOKBACK_IN_ROUND   = 1;
    uint8 public constant BASE_LOOKBACK_IN_ROUND  = 4;
    uint8 public constant MAX_LOOKBACK_IN_ROUND   = 100;

    uint256 public constant MIN_LOOKBACK_IN_SEC   = 1;
    uint256 public constant BASE_LOOKBACK_IN_SEC  = 3600;
    uint256 public constant MAX_LOOKBACK_IN_SEC   = 86400;

    uint256 public constant MAX_PRICE_UNPEG_RATIO = BONE + 2 * BONE / 100;

    uint64 public constant PAUSE_WINDOW           = 86400 * 60;

    uint256 public constant FALLBACK_SPREAD       = 3 * BONE / 1000;

    bytes32 public constant FUNCTION_HASH = keccak256("_joinPool(address owner,uint256 poolAmountOut,uint256[] calldata maxAmountsIn,uint256 deadline,uint256 nonce)");
    uint256 public constant BLOCK_WAITING_TIME = 2;

}
