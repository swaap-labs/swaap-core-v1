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

import "../Math.sol";
import "../structs/Struct.sol";

library TMathMMM {

    function getLogSpreadFactor(
        int256 mean, uint256 variance,
        uint256 z, uint256 horizon
    )
    public pure
    returns (int256 x) {
        return Math.getLogSpreadFactor(mean, variance, horizon, z);
    }

    function getMMMWeight(
        uint256 tokenWeightOut,
        int256 mean, uint256 variance,
        uint256 z, uint256 horizon
    )    public pure
    returns (uint256 weight, uint256 spread)
    {
        Struct.GBMEstimation memory gbmEstimation = Struct.GBMEstimation(mean, variance, true);
        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(z, horizon);
        return Math.getMMMWeight(true, tokenWeightOut, gbmEstimation, gbmParameters);
    }

    function getTokenBalanceAtEquilibrium(
        uint256 tokenBalance1,
        uint256 tokenWeight1,
        uint256 tokenBalance2,
        uint256 tokenWeight2,
        uint256 relativePrice
    )
    public pure
    returns (uint256 balanceAtEquilibrium)
    {
        return balanceAtEquilibrium = Math.getTokenBalanceAtEquilibrium(
            tokenBalance1,
            tokenWeight1,
            tokenBalance2,
            tokenWeight2,
            relativePrice
        );
    }

//    function calcOutGivenInMMM(
//        Struct.TokenGlobal memory tokenGlobalIn,
//        Struct.TokenGlobal memory tokenGlobalOut,
//        uint256 relativePrice,
//        Struct.SwapParameters memory swapParameters,
//        Struct.GBMParameters memory gbmParameters,
//        Struct.HistoricalPricesParameters memory hpParameters
//    )
//    public pure
//    returns (uint256 spotPriceMMM, uint256 spread)
//    {
//        Struct.TokenRecord memory tokenIn = Struct.TokenRecord(
//            tokenInBalance,
//            tokenInWeight
//        );
//        Struct.LatestRound memory tokenIn = Struct.TokenRecord(
//            address oracle,
//            uint80 roundId,
//            int256 price,
//            uint256 timestamp,
//        );
//        Struct.TokenRecord memory tokenOut = Struct.TokenRecord(
//            tokenOutBalance,
//            tokenOutWeight
//        );
//        Struct.SwapParameters memory swapParameters = Struct.SwapParameters(tokenAmountIn, swapFee);
//        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(z, horizon);
//        Struct.GBMEstimation memory gbmEstimation = Struct.GBMEstimation(
//            mean, variance
//        );
//        Struct.SwapResult memory result = Math.calcOutGivenInMMM(
//            tokenGlobalIn,
//            tokenGlobalOut,
//            relativePrice,
//            swapParameters,
//            gbmParameters,
//            hpParameters
////            tokenGlobalIn, tokenGlobalOut, relativePrice, swapParameters, gbmParameters, gbmEstimation
//        );
//
//        return (result.amount, result.spread);
//    }

    function calcAdaptiveFeeGivenInAndOut(
        uint256 tokenBalanceIn,
        uint256 tokenAmountIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenAmountOut,
        uint256 tokenWeightOut
    )
    public pure
    returns (uint256)
    {
        return Math.calcAdaptiveFeeGivenInAndOut(
            tokenBalanceIn,tokenAmountIn, tokenWeightIn,
            tokenBalanceOut, tokenAmountOut, tokenWeightOut
        );
    }

    function getOutTargetGivenIn(
        uint256 tokenBalanceOut, uint256 relativePrice, uint256 tokenAmountIn
    )
    public pure
    returns (uint256)
    {
        return tokenBalanceOut - Num.bdiv(tokenAmountIn, relativePrice);
    }

}
