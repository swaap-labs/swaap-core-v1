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

import "../../structs/Struct.sol";

/**
* @title Contains the useful methods to a trader
*/
interface IPoolSwap{

    /**
    * @notice Swap two tokens given the exact amount of token in
    * @param tokenIn The address of the input token
    * @param tokenAmountIn The exact amount of tokenIn to be swapped
    * @param tokenOut The address of the received token
    * @param minAmountOut The minimum accepted amount of tokenOut to be received
    * @param maxPrice The maximum spot price accepted before the swap
    * @return tokenAmountOut The token amount out received
    * @return spotPriceAfter The spot price of tokenOut in terms of tokenIn after the swap
    */
    function swapExactAmountInMMM(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    )
    external
    returns (uint256 tokenAmountOut, uint256 spotPriceAfter);

    /**
    * @notice Computes the amount of tokenOut received when swapping a fixed amount of tokenIn
    * @param tokenIn The address of the input token
    * @param tokenAmountIn The fixed amount of tokenIn to be swapped
    * @param tokenOut The address of the received token
    * @param minAmountOut The minimum amount of tokenOut that can be received
    * @param maxPrice The maximum spot price accepted before the swap
    * @return swapResult The swap result (amount out, spread and tax base in)
    * @return priceResult The price result (spot price before & after the swap, latest oracle price in & out)
    */
    function getAmountOutGivenInMMM(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    )
    external view
    returns (Struct.SwapResult memory swapResult, Struct.PriceResult memory priceResult);

    /**
    * @notice Swap two tokens given the exact amount of token out
    * @param tokenIn The address of the input token
    * @param maxAmountIn The maximum amount of tokenIn that can be swapped
    * @param tokenOut The address of the received token
    * @param tokenAmountOut The exact amount of tokenOut to be received
    * @param maxPrice The maximum spot price accepted before the swap
    * @return tokenAmountIn The amount of tokenIn added to the pool
    * @return spotPriceAfter The spot price of token out in terms of token in after the swap
    */
    function swapExactAmountOutMMM(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    )
    external
    returns (uint256 tokenAmountIn, uint256 spotPriceAfter);

    /**
    * @notice Computes the amount of tokenIn needed to receive a fixed amount of tokenOut
    * @param tokenIn The address of the input token
    * @param maxAmountIn The maximum amount of tokenIn that can be swapped
    * @param tokenOut The address of the received token
    * @param tokenAmountOut The fixed accepted amount of tokenOut to be received
    * @param maxPrice The maximum spot price accepted before the swap
    * @return swapResult The swap result (amount in, spread and tax base in)
    * @return priceResult The price result (spot price before & after the swap, latest oracle price in & out)
    */
    function getAmountInGivenOutMMM(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    )
    external view
    returns (Struct.SwapResult memory swapResult, Struct.PriceResult memory priceResult);
}
