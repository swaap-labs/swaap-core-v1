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
        Struct.GBMEstimation memory gbmEstimation = Struct.GBMEstimation(mean, variance);
        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(z, horizon);
        return Math.getLogSpreadFactor(gbmEstimation, gbmParameters);
    }

    function getMMMWeight(
        uint256 tokenWeightOut,
        int256 mean, uint256 variance,
        uint256 z, uint256 horizon
    )    public pure
    returns (uint256 weight, uint256 spread)
    {
        Struct.GBMEstimation memory gbmEstimation = Struct.GBMEstimation(mean, variance);
        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(z, horizon);
        return Math.getMMMWeight(tokenWeightOut, gbmEstimation, gbmParameters);
    }

    function getInAmountAtPrice(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 relativePrice
    )
    public pure
    returns (uint256 amountOutAtPrice)
    {
        return Math.getInAmountAtPrice(
            tokenBalanceIn,
            tokenWeightIn,
            tokenBalanceOut,
            tokenWeightOut,
            relativePrice
        );
    }

    function calcOutGivenInMMM(
        uint256 tokenInBalance,
        uint256 tokenInWeight,
        uint256 tokenOutBalance,
        uint256 tokenOutWeight,
        uint256 tokenInAmount,
        uint256 swapFee,
        int256 mean,
        uint256 variance,
        uint256 z,
        uint256 horizon,
        uint256 quantityInAtEquilibrium
    )
    public pure
    returns (uint256 spotPriceMMM, uint256 spread)
    {
        Struct.TokenRecord memory tokenIn = Struct.TokenRecord(
            tokenInBalance,
            tokenInWeight
        );
        Struct.TokenRecord memory tokenOut = Struct.TokenRecord(
            tokenOutBalance,
            tokenOutWeight
        );
        Struct.SwapParameters memory swapParameters = Struct.SwapParameters(tokenInAmount, swapFee);
        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(z, horizon);
        Struct.GBMEstimation memory gbmEstimation = Struct.GBMEstimation(
            mean, variance
        );
        Struct.SwapResult memory result = Math._calcOutGivenInMMM(
            tokenIn, tokenOut, swapParameters, gbmParameters, gbmEstimation, quantityInAtEquilibrium
        );
        return (result.amount, result.spread);
    }
}
