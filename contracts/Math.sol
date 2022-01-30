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

pragma solidity =0.8.0;

import "./Num.sol";
import "./Const.sol";
import "./LogExpMath.sol";
import "./GeometricBrownianMotionOracle.sol";
import "./structs/Struct.sol";

/**
* @title Library in charge of the Swaap pricing computations
* @author borelien
* @dev few definitions
* shortage of tokenOut is when (balanceIn * weightOut) / (balanceOut * weightIn) > oraclePriceOut / oraclePriceIn
* abundance of tokenOut is when (balanceIn * weightOut) / (balanceOut * weightIn) < oraclePriceOut / oraclePriceIn
* equilibrium is when (balanceIn * weightOut) / (balanceOut * weightIn) = oraclePriceOut / oraclePriceIn
*/
library Math {

    /**********************************************************************************************
    // calcSpotPrice                                                                             //
    // sP = spotPrice                                                                            //
    // bI = tokenBalanceIn                ( bI / wI )         1                                  //
    // bO = tokenBalanceOut         sP =  -----------  *  ----------                             //
    // wI = tokenWeightIn                 ( bO / wO )     ( 1 - sF )                             //
    // wO = tokenWeightOut                                                                       //
    // sF = swapFee                                                                              //
    **********************************************************************************************/
    function calcSpotPrice(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 swapFee
    )
    public pure
    returns (uint256 spotPrice)
    {
        uint256 numer = Num.bdiv(tokenBalanceIn, tokenWeightIn);
        uint256 denom = Num.bdiv(tokenBalanceOut, tokenWeightOut);
        uint256 ratio = Num.bdiv(numer, denom);
        uint256 scale = Num.bdiv(Const.BONE, Num.bsub(Const.BONE, swapFee));
        return  (spotPrice = Num.bmul(ratio, scale));
    }

    /**********************************************************************************************
    // calcOutGivenIn                                                                            //
    // aO = tokenAmountOut                                                                       //
    // bO = tokenBalanceOut                                                                      //
    // bI = tokenBalanceIn              /      /            bI             \    (wI / wO) \      //
    // aI = tokenAmountIn    aO = bO * |  1 - | --------------------------  | ^            |     //
    // wI = tokenWeightIn               \      \ ( bI + ( aI * ( 1 - sF )) /              /      //
    // wO = tokenWeightOut                                                                       //
    // sF = swapFee                                                                              //
    **********************************************************************************************/
    function calcOutGivenIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountIn,
        uint256 swapFee
    )
    public pure
    returns (uint256 tokenAmountOut)
    {
        uint256 weightRatio = Num.bdiv(tokenWeightIn, tokenWeightOut);
        uint256 adjustedIn = Num.bsub(Const.BONE, swapFee);
        adjustedIn = Num.bmul(tokenAmountIn, adjustedIn);
        uint256 y = Num.bdiv(tokenBalanceIn, Num.badd(tokenBalanceIn, adjustedIn));
        uint256 foo = Num.bpow(y, weightRatio);
        uint256 bar = Num.bsub(Const.BONE, foo);
        tokenAmountOut = Num.bmul(tokenBalanceOut, bar);
        return tokenAmountOut;
    }

    /**
    * @notice Computes the spot price of tokenOut in tokenIn terms
    * @dev Two cases to consider:
    * 1) the pool is in shortage of tokenOut ==> the pool charges a spread
    * 2) the pool is in abundance of tokenOut ==> the pool doesn't charge any spread
    * The spread is charged through an increase in weightOut proportional to the GBM forecast of
    * the tokenOut_tokenIn price process, that directly translates into an increase in the spot price,
    * which is defined as such: price = (balance_in * weight_out) / (balance_in * weight_out)
    * cf whitepaper: https://www.swaap.finance/whitepaper.pdf
    * @param tokenIn The pool record on tokenIn
    * @param latestRoundIn The oracle-related information regarding tokenIn
    * @param tokenOut The pool record on tokenOut
    * @param latestRoundOut The oracle-related information regarding tokenOut
    * @param relativePrice Represents the price of tokenOut in tokenIn terms, according to the oracles
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param hpParameters The parameters for historical prices retrieval
    * @return spotPriceMMM The spot price of tokenOut in tokenIn terms
    */
    function calcSpotPriceMMM(
        Struct.TokenRecord memory tokenIn,
        Struct.LatestRound memory latestRoundIn,
        Struct.TokenRecord memory tokenOut,
        Struct.LatestRound memory latestRoundOut,
        uint256 relativePrice,
        uint256 swapFee,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    public view
    returns (uint256 spotPriceMMM)
    {
        {

            // if tokenOut is in shortage --> apply spread
            if (tokenIn.balance >= getInAmountAtPrice(
                tokenIn.balance,
                tokenIn.weight,
                tokenOut.balance,
                tokenOut.weight,
                relativePrice
            )) {

                Struct.GBMEstimation memory gbmEstimation = GeometricBrownianMotionOracle.getParametersEstimation(
                    latestRoundIn,
                    latestRoundOut,
                    hpParameters
                );

                (uint256 weight, ) = getMMMWeight(tokenOut.weight, gbmEstimation, gbmParameters);
                return (
                    spotPriceMMM = calcSpotPrice(
                        tokenIn.balance,
                        tokenIn.weight,
                        tokenOut.balance,
                        weight,
                        swapFee
                    )
                );
            }
        }

        // if tokenOut is in abundance --> no spread
        return (
            spotPriceMMM = calcSpotPrice(
                tokenIn.balance,
                tokenIn.weight,
                tokenOut.balance,
                tokenOut.weight,
                swapFee
            )
        );
    }

    /**
    * @notice Computes the log spread factor
    * @dev We define it as the quantile of a GBM process (log-normal distribution)
    * which represents the traded pair process.
    * given by the following: exponential((mean - variance/2) * horizon + z * sqrt(variance * 2 * horizon)
    * where z is the complementary error function (erfc)
    * GBM: https://en.wikipedia.org/wiki/Geometric_Brownian_motion
    * log normal: https://en.wikipedia.org/wiki/Log-normal_distribution
    * erfc: https://en.wikipedia.org/wiki/Complementary_error_function
    * @param gbmEstimation The GBM's 2 first moments estimation
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @return x The log spread factor
    */
    function getLogSpreadFactor(
        Struct.GBMEstimation memory gbmEstimation,
        Struct.GBMParameters memory gbmParameters
    )
    public pure
    returns (int256 x)
    {
        require(gbmParameters.horizon >= 0, "NEGATIVE_HORIZON");
        require(gbmEstimation.variance >= 0, "NEGATIVE_VARIANCE");
        if (gbmEstimation.mean == 0 && gbmEstimation.variance == 0) {
            return 0;
        }
        int256 driftTerm = gbmEstimation.mean - int256(gbmEstimation.variance) / 2;
        if (driftTerm < 0) {
            driftTerm = -int256(Num.bmul(uint256(-driftTerm), gbmParameters.horizon));
        } else {
            driftTerm = int256(Num.bmul(uint256(driftTerm), gbmParameters.horizon));
        }
        uint256 diffusionTerm;
        if (gbmEstimation.variance > 0) {
            diffusionTerm = Num.bmul(
                gbmParameters.z,
                LogExpMath.pow(
                    Num.bmul(gbmEstimation.variance, 2 * gbmParameters.horizon),
                    5 * Const.BONE / 10
                )
            );
        }
        return (x = int256(diffusionTerm) + driftTerm);
    }

    /**
    * @notice Apply to the tokenWeightOut a 'spread' factor
    * @dev The spread factor is defined as the maximum between:
    a) the expected relative tokenOut increase in tokenIn terms
    b) 1
    * @param tokenWeightOut The tokenOut's weight
    * @param gbmEstimation The GBM's 2 first moments estimation
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @return the modified tokenWeightOut and its corresponding spread
    */
    function getMMMWeight(
        uint256 tokenWeightOut,
        Struct.GBMEstimation memory gbmEstimation,
        Struct.GBMParameters memory gbmParameters
    )
    public pure
    returns (uint256, uint256)
    {
        if (gbmParameters.horizon == 0) {
            return (tokenWeightOut, 0);
        }
        int256 logSpreadFactor = getLogSpreadFactor(gbmEstimation, gbmParameters);
        if (logSpreadFactor <= 0) {
            return (tokenWeightOut, 0);
        }
        uint256 spreadFactor = uint256(LogExpMath.exp(logSpreadFactor));
        // if spread < 1 --> rounding error --> set to 1
        if (spreadFactor < Const.BONE) {
            spreadFactor = Const.BONE;
        }
        uint256 spread = spreadFactor - Const.BONE;
        return (Num.bmul(tokenWeightOut, spreadFactor), spread);
    }

    /**
    * @notice Computes the net value of a given tokenIn amount in tokenOut terms
    * @dev A spread is applied as soon as entering a "shortage of tokenOut" phase
    * cf whitepaper: https://www.swaap.finance/whitepaper.pdf
    * @param tokenIn The pool record on tokenIn
    * @param latestRoundIn The oracle-related information regarding tokenIn
    * @param tokenOut The pool record on tokenOut
    * @param latestRoundOut The oracle-related information regarding tokenOut
    * @param relativePrice Represents the price of tokenOut in tokenIn terms, according to the oracles
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param hpParameters The parameters for historical prices retrieval
    * @return The swap execution conditions
    */
    function calcOutGivenInMMM(
        Struct.TokenRecord memory tokenIn,
        Struct.LatestRound memory latestRoundIn,
        Struct.TokenRecord memory tokenOut,
        Struct.LatestRound memory latestRoundOut,
        uint256 relativePrice,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    public view
    returns (Struct.SwapResult memory)
    {

        // determines the amount at equilibrium (cf definitions)
        uint256 quantityInAtEquilibrium = getInAmountAtPrice(
            tokenIn.balance,
            tokenIn.weight,
            tokenOut.balance,
            tokenOut.weight,
            relativePrice
        );

        // from abundance to abundance --> no spread
        if (tokenIn.balance < quantityInAtEquilibrium && swapParameters.amount < quantityInAtEquilibrium - tokenIn.balance) {
            return (
                Struct.SwapResult(
                    calcOutGivenIn(
                        tokenIn.balance,
                        tokenIn.weight,
                        tokenOut.balance,
                        tokenOut.weight,
                        swapParameters.amount,
                        swapParameters.fee
                    ),
                    0
                )
            );
        }

        {
            Struct.GBMEstimation memory gbmEstimation = GeometricBrownianMotionOracle.getParametersEstimation(
                latestRoundIn, latestRoundOut,
                hpParameters
            );

            return _calcOutGivenInMMM(
                tokenIn, tokenOut,
                swapParameters, gbmParameters, gbmEstimation,
                quantityInAtEquilibrium);
        }

    }

    /**
    * @notice Implements calcOutGivenInMMM in a subspace
    * @dev A spread is applied as soon as entering a "shortage of tokenOut" phase
    * cf whitepaper: https://www.swaap.finance/whitepaper.pdf
    * @param tokenIn The pool record on tokenIn
    * @param tokenOut The pool record on tokenOut
    * @param swapParameters The parameters of the swap
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param gbmEstimation The GBM's 2 first moments estimation
    * @param quantityInAtEquilibrium The amount of tokenIn at equilibrium
    * @return The swap execution conditions
    */
    function _calcOutGivenInMMM(
        Struct.TokenRecord memory tokenIn, Struct.TokenRecord memory tokenOut,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.GBMEstimation memory gbmEstimation,
        uint256 quantityInAtEquilibrium
    ) public pure returns (Struct.SwapResult memory) {

        if (gbmEstimation.mean == 0 && gbmEstimation.variance == 0) {
            // no historical signal --> no spread
            return (
                Struct.SwapResult(
                    calcOutGivenIn(
                        tokenIn.balance,
                        tokenIn.weight,
                        tokenOut.balance,
                        tokenOut.weight,
                        swapParameters.amount,
                        swapParameters.fee
                    ),
                    0
                )
            );
        }

        // tokenOut.weight increased by GBM forecast / spread factor
        (uint256 adjustedTokenOutWeight, uint256 spread) = getMMMWeight(tokenOut.weight, gbmEstimation, gbmParameters);

        if (tokenIn.balance >= quantityInAtEquilibrium) {
            // shortage of tokenOut --> apply spread
            return (
                Struct.SwapResult(
                    calcOutGivenIn(
                            tokenIn.balance,
                            tokenIn.weight,
                            tokenOut.balance,
                            adjustedTokenOutWeight,
                            swapParameters.amount,
                            swapParameters.fee
                        ),
                    spread
                )
            );
        }

        // spread may be applied, depending on quantities
        return (
            Struct.SwapResult(
               _calcOutGivenInMMMAbundance(
                    tokenIn, tokenOut,
                    swapParameters,
                    adjustedTokenOutWeight,
                    quantityInAtEquilibrium - tokenIn.balance
                ),
                 spread // TODO: apply only on tokenInSellAmountForEquilibrium
            )
        );
    }

    /**
    * @notice Implements 'calcOutGivenInMMM' in the case of abundance
    * @dev Two cases to consider:
    * 1) amount of tokenIn won't drive the pool from abundance to shortage ==> 1 pricing (no spread)
    * 2) amount of tokenIn will drive the pool from abundance to shortage ==> 2 pricing, one for each phase
    * @param tokenIn The pool record on tokenIn
    * @param tokenOut The pool record on tokenOut
    * @param swapParameters The parameters of the swap
    * @param adjustedTokenWeightOut The spread-augmented tokenOut's weight
    * @param tokenInSellAmountForEquilibrium The abundance amount of tokenIn
    * @return tokenAmountOut The swap execution conditions
    */
    function _calcOutGivenInMMMAbundance(
        Struct.TokenRecord memory tokenIn,
        Struct.TokenRecord memory tokenOut,
        Struct.SwapParameters memory swapParameters,
        uint256 adjustedTokenWeightOut,
        uint256 tokenInSellAmountForEquilibrium
    )
    internal pure
    returns (uint256 tokenAmountOut)
    {

        // should not enter if called from calcOutGivenInMMM, as this latter returns before
        // calling this function if the following condition is met
        if (swapParameters.amount < tokenInSellAmountForEquilibrium) {
            // toward equilibrium --> no spread
            return (
                tokenAmountOut = calcOutGivenIn(
                    tokenIn.balance,
                    tokenIn.weight,
                    tokenOut.balance,
                    tokenOut.weight,
                    swapParameters.amount,
                    swapParameters.fee
                )
            );
        }

        // 'abundance of tokenOut' phase --> no spread
        uint256 tokenAmountOutPart1 = calcOutGivenIn(
            tokenIn.balance,
            tokenIn.weight,
            tokenOut.balance,
            tokenOut.weight,
            tokenInSellAmountForEquilibrium,
            swapParameters.fee
        );

        // 'shortage of tokenOut phase' --> apply spread
        uint256 tokenAmountOutPart2 = calcOutGivenIn(
            tokenIn.balance + tokenInSellAmountForEquilibrium,
            tokenIn.weight,
            tokenOut.balance - tokenAmountOutPart1,
            adjustedTokenWeightOut,
            swapParameters.amount - tokenInSellAmountForEquilibrium, // tokenAmountIn > tokenInSellAmountForEquilibrium
            swapParameters.fee
        );

        return (tokenAmountOut = tokenAmountOutPart1 + tokenAmountOutPart2);
    }

    /**
    * @notice Computes the balance of tokenIn the pool must have in order to offer a tokenOut price of relativePrice
    * while satisfying the pricing curve prod^k balance_k^w_k = K
    * @dev We only rely on the following equations:
    * a) priceTokenOutOutInTokenIn = balance_in / balance_out * w_out / w_in
    * b) tokenBalanceOut = (K / prod_k!=in balance_k^w_k)^(1/w_out) = (localInvariant / balance_in^w_in)^(1/w_out)
    * with localInvariant = balance_in^w_in * balance_out^w_out which can be computed with only In/Out
    * @param tokenBalanceIn The balance of tokenIn
    * @param tokenWeightIn The weight of tokenIn
    * @param tokenBalanceOut The balance of tokenOut
    * @param tokenWeightOut The weight of tokenOut
    * @param relativePrice The price of tokenOut in tokenIn terms
    * @return amountInAtPrice The balance of tokenIn the pool must have in order to offer a tokenOut price of relativePrice
    */
    function getInAmountAtPrice(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 relativePrice
    )
    public pure
    returns (uint256 amountInAtPrice)
    {
        //        uint256 localInvariant = tokenBalanceIn^tokenWeightIn * tokenBalanceOut^tokenWeightOut
        //        uint256 price = tokenBalanceIn / (localInvariant / tokenBalanceIn^wIn)^(1/wOut) * tokenWeightOut / tokenWeightIn;
        //        uint256 price = tokenBalanceIn^(1+wIn/wOut) / (localInvariant)^(1/wOut) * tokenWeightOut / tokenWeightIn;
        //        uint256 tokenBalanceIn^(1+wIn/wOut) = price * (localInvariant)^(1/wOut) * tokenWeightIn / tokenWeightOut;
        //        uint256 tokenBalanceIn = (price * (localInvariant)^(1/wOut) * tokenWeightIn / tokenWeightOut)^(wOut/(wIn+wOut));
        //        uint256 tokenBalanceIn = (price * tokenWeightIn / tokenWeightOut)^(wOut/(wIn+wOut)) * (localInvariant)^(1/(wIn+wOut);
        {
            uint256 weightSum = tokenWeightIn + tokenWeightOut;
            uint256 wOutOverSum = Num.bdiv(tokenWeightOut, weightSum);
            amountInAtPrice = Num.bmul(
                LogExpMath.pow(
                    Num.bmul(relativePrice, Num.bdiv(tokenWeightIn, tokenWeightOut)),
                    wOutOverSum
                ),
                Num.bmul(
                    LogExpMath.pow(tokenBalanceIn, Num.bdiv(tokenWeightIn, weightSum)),
                    LogExpMath.pow(tokenBalanceOut, wOutOverSum)
                )
            );
        }
        return amountInAtPrice;

    }

}