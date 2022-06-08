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

/**
* @title Contains the useful methods to a liquidity provider
*/
interface IPoolLP {
    
    /**
    * @notice Add liquidity to a pool and credit msg.sender
    * @dev The order of maxAmount of each token must be the same as the _tokens' addresses stored in the pool
    * @param poolAmountOut Amount of pool shares a LP wishes to receive
    * @param maxAmountsIn Maximum accepted token amount in
    */
    function joinPool(
        uint256 poolAmountOut,
        uint256[] calldata maxAmountsIn
    )
    external;

    /**
    * @notice Get the token amounts in required and pool shares received when joining
    * the pool given an amount of tokenIn
    * @dev The amountIn of the specified token as input may differ at the exit due to
    * rounding discrepancies
    * @param  tokenIn The address of tokenIn
    * @param  tokenAmountIn The approximate amount of tokenIn to be swapped
    * @return poolAmountOut The pool amount out received
    * @return tokenAmountsIn The exact amounts of tokenIn needed
    */
    function getJoinPool(
        address tokenIn,
        uint256 tokenAmountIn
    )
    external
    view
    returns (uint256 poolAmountOut, uint256[] memory tokenAmountsIn);

    /**
    * @notice Remove liquidity from a pool
    * @dev The order of minAmount of each token must be the same as the _tokens' addresses stored in the pool
    * @param poolAmountIn Amount of pool shares a LP wishes to liquidate for tokens
    * @param minAmountsOut Minimum accepted token amount out
    */
    function exitPool(
        uint256 poolAmountIn,
        uint256[] calldata minAmountsOut
    )
    external;
    
    /**
    * @notice Get the token amounts received for a given pool shares in
    * @param poolAmountIn The amount of pool shares a LP wishes to liquidate for tokens
    * @return tokenAmountsOut The token amounts received
    */
    function getExitPool(uint256 poolAmountIn)
    external
    view
    returns (uint256[] memory tokenAmountsOut);

    /**
    * @notice Join a pool with a single asset with a fixed amount in
    * @dev The remaining tokens designate the tokens whose balances do not change during the joinswap
    * @param tokenIn The address of tokenIn
    * @param tokenAmountIn The amount of tokenIn to be added to the pool
    * @param minPoolAmountOut The minimum amount of pool tokens that can be received
    * @return poolAmountOut The received pool amount out
    */
    function joinswapExternAmountInMMM(
        address tokenIn,
        uint tokenAmountIn,
        uint minPoolAmountOut
    )
    external
    returns (uint poolAmountOut);

    /**
    * @notice Computes the amount of pool tokens received when joining a pool with a single asset of fixed amount in
    * @dev The remaining tokens designate the tokens whose balances do not change during the joinswap
    * @param tokenIn The address of tokenIn
    * @param tokenAmountIn The amount of tokenIn to be added to the pool
    * @return poolAmountOut The received pool token amount out
    */
    function getJoinswapExternAmountInMMM(
        address tokenIn,
        uint256 tokenAmountIn
    )
    external
    view
    returns (uint256 poolAmountOut);

    /**
    * @notice Exit a pool with a single asset given the pool token amount in
    * @dev The remaining tokens designate the tokens whose balances do not change during the exitswap
    * @param tokenOut The address of tokenOut
    * @param poolAmountIn The fixed amount of pool tokens in
    * @param minAmountOut The minimum amount of token out that can be receied
    * @return tokenAmountOut The received token amount out
    */
    function exitswapPoolAmountInMMM(
        address tokenOut,
        uint poolAmountIn,
        uint minAmountOut
    )
    external
    returns (uint tokenAmountOut);

}