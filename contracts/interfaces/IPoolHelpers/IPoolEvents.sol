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

/**
* @title Contains the pool's events
*/
interface IPoolEvents {
    
    /**
    * @notice Emitted after each swap
    * @param caller The trader's address
    * @param tokenIn The tokenIn's address
    * @param tokenOut The tokenOut's address
    * @param tokenAmountIn The amount of the swapped tokenIn
    * @param tokenAmountOut The amount of the swapped tokenOut
    * @param spread The spread
    * @param taxBaseIn The amount of tokenIn swapped when in shortage of tokenOut
    * @param priceIn The latest price of tokenIn given by the oracle
    * @param priceOut The latest price of tokenOut given by the oracle
    */
    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256         tokenAmountIn,
        uint256         tokenAmountOut,
        uint256         spread,
        uint256         taxBaseIn,
        uint256         priceIn,
        uint256         priceOut
    );

    /**
    * @notice Emitted when an LP joins the pool with 1 or multiple assets
    * @param caller The LP's address
    * @param tokenIn The dposited token's address
    * @param tokenAmountIn The deposited amount of tokenIn
    */
    event LOG_JOIN(
        address indexed caller,
        address indexed tokenIn,
        uint256         tokenAmountIn
    );

    /**
    * @notice Emitted when an LP withdraws one or multiple assets from the pool
    * @param caller The LP's address
    * @param tokenOut The withdrawn token's address
    * @param tokenAmountOut The withdrawn amount of tokenOut
    */
    event LOG_EXIT(
        address indexed caller,
        address indexed tokenOut,
        uint256         tokenAmountOut
    );

    /**
    * @param sig The function's signature
    * @param caller The caller's address
    * @param data The input data of the call
    */
    event LOG_CALL(
        bytes4  indexed sig,
        address indexed caller,
        bytes           data
    ) anonymous;

    /**
    * @notice Emitted when a new controller is assigned to the pool
    * @param from The previous controller's address
    * @param to The new controller's address
    */
    event LOG_NEW_CONTROLLER(
        address indexed from,
        address indexed to
    );

    /**
    * @notice Emitted when a token is binded/rebinded
    * @param token The binded token's address
    * @param oracle The assigned oracle's address
    * @param price The latest token's price reported by the oracle
    * @param description The oracle's description
    */
    event LOG_NEW_ORACLE_STATE(
        address indexed token,
        address oracle,
        uint256 price,
        uint8   decimals,
        string  description
    );

}