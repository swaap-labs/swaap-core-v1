// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General public License for more details.

// You should have received a copy of the GNU General public License
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
    internal pure
    returns (uint256 spotPrice)
    {
        uint256 numer = Num.bdiv(tokenBalanceIn, tokenWeightIn);
        uint256 denom = Num.bdiv(tokenBalanceOut, tokenWeightOut);
        uint256 ratio = Num.bdiv(numer, denom);
        uint256 scale = Num.bdiv(Const.BONE, Const.BONE - swapFee);
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
    internal pure
    returns (uint256 tokenAmountOut)
    {
        uint256 weightRatio = Num.bdiv(tokenWeightIn, tokenWeightOut);
        uint256 adjustedIn = Const.BONE - swapFee;
        adjustedIn = Num.bmul(tokenAmountIn, adjustedIn);
        uint256 y = Num.bdiv(tokenBalanceIn, tokenBalanceIn + adjustedIn);
        uint256 foo = Num.bpow(y, weightRatio);
        uint256 bar = Const.BONE - foo;
        tokenAmountOut = Num.bmul(tokenBalanceOut, bar);
        return tokenAmountOut;
    }

    /**********************************************************************************************
    // calcInGivenOut                                                                            //
    // aI = tokenAmountIn                                                                        //
    // bO = tokenBalanceOut               /  /     bO      \    (wO / wI)      \                 //
    // bI = tokenBalanceIn          bI * |  | ------------  | ^            - 1  |                //
    // aO = tokenAmountOut    aI =        \  \ ( bO - aO ) /                   /                 //
    // wI = tokenWeightIn           --------------------------------------------                 //
    // wO = tokenWeightOut                          ( 1 - sF )                                   //
    // sF = swapFee                                                                              //
    **********************************************************************************************/
    function calcInGivenOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountOut,
        uint swapFee
    )
    internal pure
    returns (uint tokenAmountIn)
    {
        uint weightRatio = Num.bdiv(tokenWeightOut, tokenWeightIn);
        uint diff = tokenBalanceOut - tokenAmountOut;
        uint y = Num.bdiv(tokenBalanceOut, diff);
        uint foo = Num.bpow(y, weightRatio);
        foo = foo - Const.BONE;
        tokenAmountIn = Const.BONE - swapFee;
        tokenAmountIn = Num.bdiv(Num.bmul(tokenBalanceIn, foo), tokenAmountIn);
        return tokenAmountIn;
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
    internal view
    returns (uint256 spotPriceMMM)
    {
        {

            // if tokenOut is in shortage --> apply spread
            if (tokenIn.balance >= getTokenBalanceAtEquilibrium(
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
    internal pure
    returns (int256 x)
    {
        require(gbmParameters.horizon >= 0, "NEGATIVE_HORIZON");
        require(gbmEstimation.variance >= 0, "NEGATIVE_VARIANCE");
        if (gbmEstimation.mean == 0 && gbmEstimation.variance == 0) {
            return 0;
        }
        int256 driftTerm = gbmEstimation.mean - (int256(gbmEstimation.variance) / 2);
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
    internal pure
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
    * @param swapParameters Amount of token in and swap fee
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
    internal view
    returns (Struct.SwapResult memory)
    {

        // determines the balance of tokenIn at equilibrium (cf definitions)
        uint256 balanceInAtEquilibrium = getTokenBalanceAtEquilibrium(
            tokenIn.balance,
            tokenIn.weight,
            tokenOut.balance,
            tokenOut.weight,
            relativePrice
        );

        // from abundance of tokenOut to abundance of tokenOut --> no spread
        if (tokenIn.balance < balanceInAtEquilibrium && swapParameters.amount < balanceInAtEquilibrium - tokenIn.balance) {
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
                balanceInAtEquilibrium
            );
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
    * @param balanceInAtEquilibrium The amount of tokenIn at equilibrium
    * @return The swap execution conditions
    */
    function _calcOutGivenInMMM(
        Struct.TokenRecord memory tokenIn, Struct.TokenRecord memory tokenOut,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.GBMEstimation memory gbmEstimation,
        uint256 balanceInAtEquilibrium
    ) internal pure returns (Struct.SwapResult memory) {

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

        if (tokenIn.balance >= balanceInAtEquilibrium) {
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
                    balanceInAtEquilibrium - tokenIn.balance
                ),
                spread // TODO: broadcast necessary data to compute accurate fee revenue
            )
        );
    }

    /**
    * @notice Implements 'calcOutGivenInMMM' in the case of abundance of tokenOut
    * @dev Two cases to consider:
    * 1) amount of tokenIn won't drive the pool from abundance of tokenOut to shortage ==> 1 pricing (no spread)
    * 2) amount of tokenIn will drive the pool from abundance of tokenOut to shortage ==> 2 pricing, one for each phase
    * @param tokenIn The pool record on tokenIn
    * @param tokenOut The pool record on tokenOut
    * @param swapParameters The parameters of the swap
    * @param adjustedTokenWeightOut The spread-augmented tokenOut's weight
    * @param tokenInSellAmountForEquilibrium TokenIn needed to reach equilibrium
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
        if (swapParameters.amount <= tokenInSellAmountForEquilibrium) {
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
    * @notice Computes the amount of tokenIn needed in order to receive a given amount of tokenOut
    * @dev A spread is applied as soon as entering a "shortage of tokenOut" phase
    * cf whitepaper: https://www.swaap.finance/whitepaper.pdf
    * @param tokenIn The pool record on tokenIn
    * @param latestRoundIn The oracle-related information regarding tokenIn
    * @param tokenOut The pool record on tokenOut
    * @param latestRoundOut The oracle-related information regarding tokenOut
    * @param relativePrice Represents the price of tokenOut in tokenIn terms, according to the oracles
    * @param swapParameters Amount of token out and swap fee
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param hpParameters The parameters for historical prices retrieval
    * @return The swap execution conditions
    */
    function calcInGivenOutMMM(
        Struct.TokenRecord memory tokenIn,
        Struct.LatestRound memory latestRoundIn,
        Struct.TokenRecord memory tokenOut,
        Struct.LatestRound memory latestRoundOut,
        uint256 relativePrice,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    internal view
    returns (Struct.SwapResult memory)
    {

        // determines the balance of tokenOut at equilibrium (cf definitions)
        uint256 balanceOutAtEquilibrium = getTokenBalanceAtEquilibrium(
            tokenOut.balance,
            tokenOut.weight,
            tokenIn.balance,
            tokenIn.weight,
            relativePrice
        );

        // from abundance of tokenOut to abundance of tokenOut --> no spread
        if (tokenOut.balance > balanceOutAtEquilibrium && swapParameters.amount < tokenOut.balance - balanceOutAtEquilibrium) {
            return (
                Struct.SwapResult(
                    calcInGivenOut(
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

            return _calcInGivenOutMMM(
                tokenIn, tokenOut,
                swapParameters, gbmParameters, gbmEstimation,
                balanceOutAtEquilibrium
            );
        }

    }

    /**
    * @notice Implements calcInGivenOutMMM in a subspace
    * @dev A spread is applied as soon as entering a "shortage of tokenOut" phase
    * cf whitepaper: https://www.swaap.finance/whitepaper.pdf
    * @param tokenIn The pool record on tokenIn
    * @param tokenOut The pool record on tokenOut
    * @param swapParameters The parameters of the swap
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param gbmEstimation The GBM's 2 first moments estimation
    * @param balanceOutAtEquilibrium The amount of tokenOut at equilibrium
    * @return The swap execution conditions
    */
    function _calcInGivenOutMMM(
        Struct.TokenRecord memory tokenIn, Struct.TokenRecord memory tokenOut,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.GBMEstimation memory gbmEstimation,
        uint256 balanceOutAtEquilibrium
    ) internal pure returns (Struct.SwapResult memory) {

        if (gbmEstimation.mean == 0 && gbmEstimation.variance == 0) {
            // no historical signal --> no spread
            return (
                Struct.SwapResult(
                    calcInGivenOut(
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

        if (tokenOut.balance <= balanceOutAtEquilibrium) {
            // shortage of tokenOut --> apply spread
            return (
            Struct.SwapResult(
                calcInGivenOut(
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
                _calcInGivenOutMMMAbundance(
                    tokenIn, tokenOut,
                    swapParameters,
                    adjustedTokenOutWeight,
                    tokenOut.balance - balanceOutAtEquilibrium
                ),
                spread // TODO: broadcast necessary data to compute accurate fee revenue
            )
        );
    }

    /**
    * @notice Implements 'calcInGivenOutMMM' in the case of abundance of tokenOut
    * @dev Two cases to consider:
    * 1) amount of tokenIn won't drive the pool from abundance of tokenOut to shortage ==> 1 pricing (no spread)
    * 2) amount of tokenIn will drive the pool from abundance of tokenOut to shortage ==> 2 pricing, one for each phase
    * @param tokenIn The pool record on tokenIn
    * @param tokenOut The pool record on tokenOut
    * @param swapParameters The parameters of the swap
    * @param adjustedTokenWeightOut The spread-augmented tokenOut's weight
    * @param tokenOutBuyAmountForEquilibrium TokenOut needed to reach equilibrium
    * @return tokenAmountIn TokenIn Amount needed for the swap
    */
    function _calcInGivenOutMMMAbundance(
        Struct.TokenRecord memory tokenIn,
        Struct.TokenRecord memory tokenOut,
        Struct.SwapParameters memory swapParameters,
        uint256 adjustedTokenWeightOut,
        uint256 tokenOutBuyAmountForEquilibrium
    )
    internal pure
    returns (uint256 tokenAmountIn)
    {
        // should not enter if called from calcInGivenOutMMM, as this latter returns before
        // calling this function if the following condition is met
        if (swapParameters.amount <= tokenOutBuyAmountForEquilibrium) {
            // toward equilibrium --> no spread
            return (
                tokenAmountIn = calcInGivenOut(
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
        uint256 tokenAmountInPart1 = calcInGivenOut(
            tokenIn.balance,
            tokenIn.weight,
            tokenOut.balance,
            tokenOut.weight,
            tokenOutBuyAmountForEquilibrium,
            swapParameters.fee
        );

        // 'shortage of tokenOut phase' --> apply spread
        uint256 tokenAmountInPart2 = calcInGivenOut(
            tokenIn.balance + tokenAmountInPart1,
            tokenIn.weight,
            tokenOut.balance - tokenOutBuyAmountForEquilibrium,
            adjustedTokenWeightOut,
            swapParameters.amount - tokenOutBuyAmountForEquilibrium, // tokenAmountOut > tokenOutBuyAmountForEquilibrium
            swapParameters.fee
        );

        return (tokenAmountIn = tokenAmountInPart1 + tokenAmountInPart2);
    }

    /**
    * @notice Computes the balance of token1 the pool must have in order to have token1/token2 at equilibrium
    * while satisfying the pricing curve prod^k balance_k^w_k = K
    * @dev We only rely on the following equations:
    * a) priceTokenOutOutInTokenIn = balance_in / balance_out * w_out / w_in
    * b) tokenBalanceOut = (K / prod_k!=in balance_k^w_k)^(1/w_out) = (localInvariant / balance_in^w_in)^(1/w_out)
    * with localInvariant = balance_in^w_in * balance_out^w_out which can be computed with only In/Out
    * @param tokenBalance1 The balance of token1 initially
    * @param tokenWeight1 The weight of token1
    * @param tokenBalance2 The balance of token2 initially
    * @param tokenWeight2 The weight of token2
    * @param relativePrice The price of token1 in terms of token2
    * @return balance1AtEquilibrium The balance of token1 in order to have a token1/token2 at equilibrium
    */
    function getTokenBalanceAtEquilibrium(
        uint256 tokenBalance1,
        uint256 tokenWeight1,
        uint256 tokenBalance2,
        uint256 tokenWeight2,
        uint256 relativePrice
    )
    internal pure
    returns (uint256 balance1AtEquilibrium)
    {
        {
            uint256 weightSum = tokenWeight1 + tokenWeight2;
            uint256 wOutOverSum = Num.bdiv(tokenWeight2, weightSum);
            balance1AtEquilibrium = Num.bmul(
                LogExpMath.pow(
                    Num.bmul(relativePrice, Num.bdiv(tokenWeight1, tokenWeight2)),
                    wOutOverSum
                ),
                Num.bmul(
                    LogExpMath.pow(tokenBalance1, Num.bdiv(tokenWeight1, weightSum)),
                    LogExpMath.pow(tokenBalance2, wOutOverSum)
                )
            );
        }
        return balance1AtEquilibrium;

    }

}
