// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General internal License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General internal License for more details.

// You should have received a copy of the GNU General internal License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.8.0;

import "./contracts/Pool.sol";
import "./MyToken.sol";
import "./CryticInterface.sol";
import "./contracts/test/TWBTCOracle.sol";
import "./contracts/test/TWETHOracle.sol";


contract TPoolSwap is CryticInterface, Pool {

    uint256 initial_token_balance = type(uint).max;

    MyToken t1;
    TWBTCOracle oracle1;

    MyToken t2;
    TWETHOracle oracle2;

    uint256 seed = Const.BONE;

    uint256 balance = 1000000 * Const.BONE;

    constructor() {
        // set Oracle for each token
        oracle1 = new TWBTCOracle(block.timestamp);
        oracle2 = new TWETHOracle(block.timestamp);

        // two tokens with minimal balances and weights are created by the controller
        t1 = new MyToken(initial_token_balance, address(this));
        bindMMM(address(t1), balance, Const.MIN_WEIGHT, address(oracle1));
        t2 = new MyToken(initial_token_balance, address(this));
        bindMMM(address(t2), balance, Const.MIN_WEIGHT, address(oracle2));
        finalize();
    }

    function rebind_t1(uint256 balance, uint256 denorm) public {
        rebind(address(t1), denorm);
    }

    function rebind_t2(uint256 balance, uint256 denorm) public {
        rebind(address(t2), denorm);
    }

    function rebind(address token, uint256 denorm) public {
        rebindMMM(
            token,
//            balance % (IERC20(token).balanceOf(msg.sender) / 2),
            balance,
            denorm % (Const.MAX_WEIGHT / 2),
            address(oracle2)
        );
    }

    function add_oracle_data_point_t1(int256 value) public {
        oracle1.addDataPoint(value, block.timestamp);
    }

    function add_oracle_data_point_t2(int256 value) public {
        oracle2.addDataPoint(value, block.timestamp);
    }

    function set_seed(uint256 value) public {
        seed = value;
    }

    function echidna_swap_t1_t2() public returns (bool) {
        return swap(address(t1), address(t2), seed);
    }

    function echidna_swap_t2_t1() public returns (bool) {
        return swap(address(t1), address(t2), seed);
    }

    function swap(address tokenIn, address tokenOut, uint256 s) internal returns (bool) {
        uint256 reserveIn = this.getBalance(tokenIn);
        // if the user has a small balance, it should be able to swap it
        uint256 tokenAmountIn = s % (reserveIn / 100);
        uint tokenAmountInBack = tokenAmountIn;
        if (IERC20(tokenIn).balanceOf(msg.sender) > tokenAmountIn) {
            (uint256 tokenAmountOut, ) = swapExactAmountInMMM(
                tokenIn,
                tokenAmountIn,
                tokenOut,
                0,
                type(uint).max
            );
            (tokenAmountInBack, ) = swapExactAmountInMMM(
                tokenOut,
                tokenAmountOut,
                tokenIn,
                0,
                type(uint).max
            );
        }
        return tokenAmountIn >= tokenAmountInBack;
    }

}
