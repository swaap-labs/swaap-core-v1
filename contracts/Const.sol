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

library Const {
    uint256 public constant ONE                       = 10**18;

    uint256 public constant MIN_BOUND_TOKENS           = 2;
    uint256 public constant MAX_BOUND_TOKENS           = 8;

    uint256 public constant MIN_FEE                    = ONE / 10**6;
    uint256 public constant BASE_FEE                   = 25 * ONE / 10**5;
    uint256 public constant MAX_FEE                    = ONE / 10;
    uint256 public constant EXIT_FEE                   = 0;

    uint80 public constant MIN_WEIGHT                  = uint80(ONE);
    uint80 public constant MAX_WEIGHT                  = uint80(ONE * 50);
    uint80 public constant MAX_TOTAL_WEIGHT            = uint80(ONE * 50);
    uint256 public constant MIN_BALANCE                = ONE / 10**12;

    uint256 public constant INIT_POOL_SUPPLY           = ONE * 100;

    uint256 public constant MIN_POW_BASE              = 1 wei;
    uint256 public constant MAX_POW_BASE              = (2 * ONE) - 1 wei;
    uint256 public constant POW_PRECISION             = ONE / 10**10;

    uint public constant MAX_IN_RATIO                  = ONE / 2;
    uint public constant MAX_OUT_RATIO                 = (ONE / 3) + 1 wei;

    uint64 public constant BASE_Z                      = uint64(6 * ONE / 10);

    uint256 public constant MIN_HORIZON                = 1 * ONE;
    uint256 public constant BASE_HORIZON               = 300 * ONE;

    uint8 public constant MIN_LOOKBACK_IN_ROUND        = 1;
    uint8 public constant BASE_LOOKBACK_IN_ROUND       = 4;
    uint8 public constant MAX_LOOKBACK_IN_ROUND        = 100;

    uint256 public constant MIN_LOOKBACK_IN_SEC        = 1;
    uint256 public constant BASE_LOOKBACK_IN_SEC       = 3600;

    uint256 public constant MIN_MAX_PRICE_UNPEG_RATIO  = ONE + ONE / 800;
    uint256 public constant BASE_MAX_PRICE_UNPEG_RATIO = ONE + ONE / 50;
    uint256 public constant MAX_MAX_PRICE_UNPEG_RATIO  = ONE + ONE / 10;

    uint64 public constant PAUSE_WINDOW                = 86400 * 60;

    uint256 public constant FALLBACK_SPREAD            = 3 * ONE / 1000;

    uint256 public constant ORACLE_TIMEOUT             = 2 * 60;

    uint8 public constant MIN_LOOKBACK_STEP_IN_ROUND   = 1;
    uint8 public constant LOOKBACK_STEP_IN_ROUND       = 3;
}
