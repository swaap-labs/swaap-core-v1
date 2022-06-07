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

import "./Num.sol";
import "./Const.sol";
import "./LogExpMath.sol";
import "./GeometricBrownianMotionOracle.sol";
import "./ChainlinkUtils.sol";
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
    // bI = tokenBalanceIn                      ( bI * w0 )                                      //
    // bO = tokenBalanceOut         sP =  ------------------------                               //
    // wI = tokenWeightIn                 ( bO * wI ) * ( 1 - sF )                               //
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
        uint256 numer = Num.mul(tokenBalanceIn, tokenWeightOut);
        uint256 denom = Num.mul(Num.mul(tokenBalanceOut, tokenWeightIn), Const.ONE - swapFee);
        return (spotPrice = Num.div(numer, denom));
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
        uint256 weightRatio = Num.div(tokenWeightIn, tokenWeightOut);
        uint256 adjustedIn = Const.ONE - swapFee;
        adjustedIn = Num.mul(tokenAmountIn, adjustedIn);
        uint256 y = Num.div(tokenBalanceIn, tokenBalanceIn + adjustedIn);
        uint256 foo = Num.pow(y, weightRatio);
        uint256 bar = Const.ONE - foo;
        tokenAmountOut = Num.mul(tokenBalanceOut, bar);
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
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountOut,
        uint256 swapFee
    )
        public pure
        returns (uint256 tokenAmountIn)
    {
        uint256 weightRatio = Num.div(tokenWeightOut, tokenWeightIn);
        uint256 diff = tokenBalanceOut - tokenAmountOut;
        uint256 y = Num.div(tokenBalanceOut, diff);
        uint256 foo = Num.pow(y, weightRatio);
        foo = foo - Const.ONE;
        tokenAmountIn = Const.ONE - swapFee;
        tokenAmountIn = Num.div(Num.mul(tokenBalanceIn, foo), tokenAmountIn);
        return tokenAmountIn;
    }

    /**********************************************************************************************
    // calcPoolOutGivenSingleIn                                                                  //
    // pAo = poolAmountOut                                                                       //
    // tAi = tokenAmountIn        //                                      \    wI   \            //
    // wI = tokenWeightIn        //                                        \  ----   \           //
    // tW = totalWeight          ||   tAi * ( tW - ( tW - wI ) * sF )      | ^ tW    |           //
    // tBi = tokenBalanceIn pAo= ||  --------------------------------- + 1 |         | * pS - pS //
    // pS = poolSupply            \\             tBi * tW                  /         /           //
    // sF = swapFee                \\                                     /         /            //
    **********************************************************************************************/
    function calcPoolOutGivenSingleIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 tokenAmountIn,
        uint256 swapFee
    )
        public pure
        returns (uint256 poolAmountOut)
    {
        // Charge the trading fee for the proportion of tokenAi
        //  which is implicitly traded to the other pool tokens.
        // That proportion is (1- weightTokenIn)
        // tokenAiAfterFee = tAi * (1 - (1-weightTi) * poolFee);

        uint256 innerNumer = Num.mul(
            tokenAmountIn,
            totalWeight -  Num.mul(
                totalWeight - tokenWeightIn,
                swapFee
            )
        );
        uint256 innerDenom = Num.mul(tokenBalanceIn, totalWeight);

        uint256 inner = Num.pow(Num.div(innerNumer, innerDenom) + Const.ONE, Num.div(tokenWeightIn, totalWeight));

        return (poolAmountOut = Num.mul(inner, poolSupply) - poolSupply);
    }

    /**
    * @notice Computes the pool token out when joining with a single asset
    * @param tokenGlobalIn The pool global information on tokenIn
    * @param remainingTokens The pool global information on the remaining tokens
    * @param joinswapParameters The joinswap's parameters (amount in, fee, fallback-spread and pool supply)
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param hpParameters The parameters for historical prices retrieval
    * @return poolAmountOut The amount of pool tokens to be received
    */
    function calcPoolOutGivenSingleInMMM(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal[] memory remainingTokens,
        Struct.JoinExitSwapParameters memory joinswapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
        public view
        returns (uint256 poolAmountOut)
    {

        // to get the total adjusted weight, we assume all the tokens Out are in shortage
        uint256 totalAdjustedWeight = getTotalWeightMMM(
            true,
            joinswapParameters.fallbackSpread,
            tokenGlobalIn,
            remainingTokens,
            gbmParameters,
            hpParameters
        );

        uint256 fee = joinswapParameters.fee;

        bool blockHasPriceUpdate = block.timestamp == tokenGlobalIn.latestRound.timestamp;
        {
            uint8 i;
            while ((!blockHasPriceUpdate) && (i < remainingTokens.length)) {
                if (block.timestamp == remainingTokens[i].latestRound.timestamp) {
                    blockHasPriceUpdate = true;
                }
                unchecked { ++i; }
            }
        }
        if (blockHasPriceUpdate) {
            uint256 poolValueInTokenIn = getPoolTotalValue(tokenGlobalIn, remainingTokens);
            fee += calcPoolOutGivenSingleInAdaptiveFees(
                poolValueInTokenIn,
                tokenGlobalIn.info.balance,
                Num.div(tokenGlobalIn.info.weight, totalAdjustedWeight),
                joinswapParameters.amount
            );
        }

        poolAmountOut = calcPoolOutGivenSingleIn(
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            joinswapParameters.poolSupply,
            totalAdjustedWeight,
            joinswapParameters.amount,
            fee
        );

        return poolAmountOut;
    }

    /**********************************************************************************************
    // calcSingleOutGivenPoolIn                                                                  //
    // tAo = tokenAmountOut            /      /                                          \\      //
    // bO = tokenBalanceOut           /      // pS - (pAi * (1 - eF)) \     /  tW  \      \\     //
    // pAi = poolAmountIn            | bO - || ----------------------- | ^ | ------ | * b0 ||    //
    // ps = poolSupply                \      \\          pS           /     \  wO  /      //     //
    // wI = tokenWeightIn      tAo =   \      \                                          //      //
    // tW = totalWeight                    /     /      wO \       \                             //
    // sF = swapFee                    *  | 1 - |  1 - ---- | * sF  |                            //
    // eF = exitFee                        \     \      tW /       /                             //
    **********************************************************************************************/
    function calcSingleOutGivenPoolIn(
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 poolAmountIn,
        uint256 swapFee
    )
    public pure
    returns (uint256 tokenAmountOut)
    {
        // charge exit fee on the pool token side
        // pAiAfterExitFee = pAi*(1-exitFee)
        uint256 poolAmountInAfterExitFee = Num.mul(poolAmountIn, Const.ONE - Const.EXIT_FEE);
        uint256 newPoolSupply = poolSupply - poolAmountInAfterExitFee;
        uint256 poolRatio = Num.div(newPoolSupply, poolSupply);

        // newBalTo = poolRatio^(1/weightTo) * balTo;
        uint256 tokenOutRatio = Num.pow(poolRatio, Num.div(totalWeight, tokenWeightOut));
        uint256 newTokenBalanceOut = Num.mul(tokenOutRatio, tokenBalanceOut);

        uint256 tokenAmountOutBeforeSwapFee = tokenBalanceOut - newTokenBalanceOut;

        // charge swap fee on the output token side
        //uint256 tAo = tAoBeforeSwapFee * (1 - (1-weightTo) * swapFee)
        uint256 zaz = Num.mul(Const.ONE - Num.div(tokenWeightOut, totalWeight), swapFee);
        tokenAmountOut = Num.mul(tokenAmountOutBeforeSwapFee, Const.ONE - zaz);
        return tokenAmountOut;
    }

    /**
    * @notice Computes the token amount out to be received when exiting the pool with a single asset
    * @param tokenGlobalOut The pool global information on tokenOut
    * @param remainingTokens The pool global information on the remaining tokens
    * @param exitswapParameters The exitswap's parameters (amount in, fee, fallback-spread and pool supply)
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param hpParameters The parameters for historical prices retrieval
    * @return tokenAmountOut The amount of tokenOut to be received
    */
    function calcSingleOutGivenPoolInMMM(
        Struct.TokenGlobal memory tokenGlobalOut,
        Struct.TokenGlobal[] memory remainingTokens,
        Struct.JoinExitSwapParameters memory exitswapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    public view
    returns (uint256 tokenAmountOut)
    {
        // to get the total adjusted weight, we assume all the remaining tokens are in shortage
        uint256 totalAdjustedWeight = getTotalWeightMMM(
            false,
            exitswapParameters.fallbackSpread,
            tokenGlobalOut,
            remainingTokens,
            gbmParameters,
            hpParameters
        );

        uint256 fee = exitswapParameters.fee;

        bool blockHasPriceUpdate = block.timestamp == tokenGlobalOut.latestRound.timestamp;
        {
            uint8 i;
            while ((!blockHasPriceUpdate) && (i < remainingTokens.length)) {
                if (block.timestamp == remainingTokens[i].latestRound.timestamp) {
                    blockHasPriceUpdate = true;
                }
                unchecked { ++i; }
            }
        }
        if (blockHasPriceUpdate) {
            uint256 poolValueInTokenOut = getPoolTotalValue(tokenGlobalOut, remainingTokens);
            fee += calcSingleOutGivenPoolInAdaptiveFees(
                poolValueInTokenOut,
                tokenGlobalOut.info.balance,
                Num.div(tokenGlobalOut.info.weight, totalAdjustedWeight),
                Num.div(exitswapParameters.amount, exitswapParameters.poolSupply)
            );
        }

        tokenAmountOut = calcSingleOutGivenPoolIn(
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            exitswapParameters.poolSupply,
            totalAdjustedWeight,
            exitswapParameters.amount,
            fee
        );

        return tokenAmountOut;
    }

    /**
    * @notice Computes the log spread factor
    * @dev We define it as the log of the p-quantile of a GBM process (log-normal distribution),
    * which is given by the following:
    * mean * horizon + z * sqrt(2 * variance * horizon)
    * where z = ierf(2p - 1), with ierf being the inverse error function.
    * GBM: https://en.wikipedia.org/wiki/Geometric_Brownian_motion
    * Log-normal distribution: https://en.wikipedia.org/wiki/Log-normal_distribution
    * erf: https://en.wikipedia.org/wiki/Error_function
    * @param mean The percentage drift
    * @param variance The percentage volatility
    * @param horizon The GBM forecast horizon parameter
    * @param z The GBM forecast z parameter
    * @return x The log spread factor
    */
    function getLogSpreadFactor(
        int256 mean, uint256 variance,
        uint256 horizon, uint256 z
    )
    public pure
    returns (int256 x)
    {
        if (mean == 0 && variance == 0) {
            return 0;
        }
        if (mean < 0) {
            mean = -int256(Num.mul(uint256(-mean), horizon));
        } else {
            mean = int256(Num.mul(uint256(mean), horizon));
        }
        uint256 diffusion;
        if (variance > 0) {
            diffusion = Num.mul(
                z,
                LogExpMath.pow(
                    Num.mul(variance, 2 * horizon),
                    Const.ONE / 2
                )
            );
        }
        return (x = int256(diffusion) + mean);
    }

    /**
    * @notice Apply to the tokenWeight a 'spread' factor
    * @dev The spread factor is defined as the maximum between:
    a) the expected relative tokenOut increase in tokenIn terms
    b) 1
    * The function multiplies the tokenWeight by the spread factor if
    * the token is in shortage, or divides it by the spread factor if it is in abundance
    * @param shortage true when the token is in shortage, false if in abundance
    * @param fallbackSpread The default spread in case the it couldn't be calculated using oracle prices
    * @param tokenWeight The token's weight
    * @param gbmEstimation The GBM's 2 first moments estimation
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @return adjustedWeight The adjusted weight based on spread
    * @return spread The spread
    */
    function getMMMWeight(
        bool shortage,
        uint256 fallbackSpread,
        uint256 tokenWeight,
        Struct.GBMEstimation memory gbmEstimation,
        Struct.GBMParameters memory gbmParameters
    )
    public pure
    returns (uint256 adjustedWeight, uint256 spread)
    {

        if (!gbmEstimation.success) {
            if (shortage) {
                return (Num.mul(tokenWeight, Const.ONE + fallbackSpread), fallbackSpread);
            } else {
                return (Num.div(tokenWeight, Const.ONE + fallbackSpread), fallbackSpread);
            }
        }

        if (gbmParameters.horizon == 0) {
            return (tokenWeight, 0);
        }

        int256 logSpreadFactor = getLogSpreadFactor(
            gbmEstimation.mean, gbmEstimation.variance,
            gbmParameters.horizon, gbmParameters.z
        );
        if (logSpreadFactor <= 0) {
            return (tokenWeight, 0);
        }
        uint256 spreadFactor = uint256(LogExpMath.exp(logSpreadFactor));
        // if spread < 1 --> rounding error --> set to 1
        if (spreadFactor <= Const.ONE) {
            return (tokenWeight, 0);
        }

        spread = spreadFactor - Const.ONE;

        if (shortage) {
            return (Num.mul(tokenWeight, spreadFactor), spread);
        } else {
            return (Num.div(tokenWeight, spreadFactor), spread);
        }
    }

    /**
    * @notice Adjusts every token's weight (except from the pivotToken) with a spread factor and computes the sum
    * @dev The initial weights of the tokens are the ones adjusted by their price performance only
    * @param pivotTokenIsInput True if and only if pivotToken should be considered as an input token
    * @param fallbackSpread The default spread in case the it couldn't be calculated using oracle prices
    * @param pivotToken The pivot token's global information (token records + latest round info)
    * @param otherTokens Other pool's tokens' global information (token records + latest rounds info)
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param hpParameters The parameters for historical prices retrieval
    * @return totalAdjustedWeight The total adjusted weight
    */
    function getTotalWeightMMM(
        bool pivotTokenIsInput,
        uint256 fallbackSpread,
        Struct.TokenGlobal memory pivotToken,
        Struct.TokenGlobal[] memory otherTokens,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    internal view
    returns (uint256 totalAdjustedWeight)
    {

        bool noMoreDataPointPivot;
        Struct.HistoricalPricesData memory hpDataPivot;

        {
            uint256[] memory pricesPivot;
            uint256[] memory timestampsPivot;
            uint256 startIndexPivot;
            // retrieve historical prices of tokenIn
            (pricesPivot,
            timestampsPivot,
            startIndexPivot,
            noMoreDataPointPivot) = GeometricBrownianMotionOracle.getHistoricalPrices(pivotToken.latestRound, hpParameters);

            hpDataPivot = Struct.HistoricalPricesData(startIndexPivot, timestampsPivot, pricesPivot);

            // reducing lookback time window
            uint256 reducedLookbackInSecCandidate = hpParameters.timestamp - timestampsPivot[startIndexPivot];
            if (reducedLookbackInSecCandidate < hpParameters.lookbackInSec) {
                hpParameters.lookbackInSec = reducedLookbackInSecCandidate;
            }
        }

        // to get the total adjusted weight, we apply a spread factor on every weight except from the pivotToken's one.
        totalAdjustedWeight = pivotToken.info.weight;
        for (uint256 i; i < otherTokens.length;) {

            (uint256[] memory pricesOthers,
            uint256[] memory timestampsOthers,
            uint256 startIndexOthers,
            bool noMoreDataPointOthers) = GeometricBrownianMotionOracle.getHistoricalPrices(otherTokens[i].latestRound, hpParameters);

            Struct.GBMEstimation memory gbmEstimation;
            if (pivotTokenIsInput) {
                // weight is increased
                gbmEstimation = GeometricBrownianMotionOracle._getParametersEstimation(
                    noMoreDataPointPivot && noMoreDataPointOthers,
                    hpDataPivot,
                    Struct.HistoricalPricesData(startIndexOthers, timestampsOthers, pricesOthers),
                    hpParameters
                );
            } else {
                // weight is reduced
                gbmEstimation = GeometricBrownianMotionOracle._getParametersEstimation(
                    noMoreDataPointPivot && noMoreDataPointOthers,
                    Struct.HistoricalPricesData(startIndexOthers, timestampsOthers, pricesOthers),
                    hpDataPivot,
                    hpParameters
                );
            }

            (otherTokens[i].info.weight, ) = getMMMWeight(
                pivotTokenIsInput,
                fallbackSpread,
                otherTokens[i].info.weight,
                gbmEstimation,
                gbmParameters
            );

            totalAdjustedWeight += otherTokens[i].info.weight;
            unchecked {++i;}
        }

        return totalAdjustedWeight;
    }

    /**
    * @notice Computes the net value of a given tokenIn amount in tokenOut terms
    * @dev A spread is applied as soon as entering a "shortage of tokenOut" phase
    * cf whitepaper: https://www.swaap.finance/whitepaper.pdf
    * @param tokenGlobalIn The pool global information on tokenIn
    * @param tokenGlobalOut The pool global information on tokenOut
    * @param relativePrice The price of tokenOut in tokenIn terms
    * @param swapParameters Amount of token in and swap fee
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param hpParameters The parameters for historical prices retrieval
    * @return swapResult The swap result (amount out, spread and tax base in)
    */
    function calcOutGivenInMMM(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal memory tokenGlobalOut,
        uint256 relativePrice,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    public view
    returns (Struct.SwapResult memory swapResult)
    {

        // determines the balance of tokenIn at equilibrium (cf definitions)
        uint256 balanceInAtEquilibrium = getTokenBalanceAtEquilibrium(
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            relativePrice
        );

        // from abundance of tokenOut to abundance of tokenOut --> no spread
        {
            if (tokenGlobalIn.info.balance < balanceInAtEquilibrium && swapParameters.amount < balanceInAtEquilibrium - tokenGlobalIn.info.balance) {
                return Struct.SwapResult(
                    _calcOutGivenInMMMAbundance(
                        tokenGlobalIn, tokenGlobalOut,
                        relativePrice,
                        swapParameters.amount,
                        swapParameters.fee,
                        swapParameters.fallbackSpread
                    ),
                    0,
                    0
                );
            }
        }

        {
            Struct.GBMEstimation memory gbmEstimation = GeometricBrownianMotionOracle.getParametersEstimation(
                tokenGlobalIn.latestRound, tokenGlobalOut.latestRound,
                hpParameters
            );

            (uint256 adjustedTokenOutWeight, uint256 spread) = getMMMWeight(
                true,
                swapParameters.fallbackSpread,
                tokenGlobalOut.info.weight,
                gbmEstimation, gbmParameters
            );

            if (tokenGlobalIn.info.balance >= balanceInAtEquilibrium) {
                // shortage to shortage
                return (
                    Struct.SwapResult(
                        calcOutGivenIn(
                            tokenGlobalIn.info.balance,
                            tokenGlobalIn.info.weight,
                            tokenGlobalOut.info.balance,
                            adjustedTokenOutWeight,
                            swapParameters.amount,
                            swapParameters.fee
                        ),
                        spread,
                        swapParameters.amount
                    )
                );
            }
            else {
                // abundance to shortage
                (uint256 amount, uint256 taxBaseIn) = _calcOutGivenInMMMMixed(
                    tokenGlobalIn,
                    tokenGlobalOut,
                    swapParameters,
                    relativePrice,
                    adjustedTokenOutWeight,
                    balanceInAtEquilibrium
                );
                return (
                    Struct.SwapResult(
                        amount,
                        spread,
                        taxBaseIn
                    )
                );
            }
        }

    }

    /**
    * @notice Implements calcOutGivenInMMM in the case of abundance of tokenOut
    * @dev A spread is applied as soon as entering a "shortage of tokenOut" phase
    * cf whitepaper: https://www.swaap.finance/whitepaper.pdf
    * @param tokenGlobalIn The pool global information on tokenIn
    * @param tokenGlobalOut The pool global information on tokenOut
    * @param relativePrice The price of tokenOut in tokenIn terms
    * @param tokenAmountIn The amount of tokenIn that will be swaped
    * @param baseFee The base fee
    * @param fallbackSpread The default spread in case the it couldn't be calculated using oracle prices
    * @return tokenAmountOut The tokenAmountOut when the tokenOut is in abundance
    */
    function _calcOutGivenInMMMAbundance(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal memory tokenGlobalOut,
        uint256 relativePrice,
        uint256 tokenAmountIn,
        uint256 baseFee,
        uint256 fallbackSpread
    ) public view returns (uint256) {
        uint256 adaptiveFees = getAdaptiveFees(
            tokenGlobalIn,
            tokenAmountIn,
            tokenGlobalOut,
            Num.div(tokenAmountIn, relativePrice),
            relativePrice,
            baseFee,
            fallbackSpread
        );
        return (
            calcOutGivenIn(
                tokenGlobalIn.info.balance,
                tokenGlobalIn.info.weight,
                tokenGlobalOut.info.balance,
                tokenGlobalOut.info.weight,
                tokenAmountIn,
                adaptiveFees
            )
        );
    }

    /**
    * @notice Implements 'calcOutGivenInMMM' in the case of mixed regime of tokenOut (abundance then shortage)
    * @param tokenGlobalIn The pool global information on tokenIn
    * @param tokenGlobalOut The pool global information on tokenOut
    * @param swapParameters The parameters of the swap
    * @param relativePrice The price of tokenOut in tokenIn terms
    * @param adjustedTokenWeightOut The spread-augmented tokenOut's weight
    * @param balanceInAtEquilibrium TokenIn balance at equilibrium
    * @return tokenAmountOut The total amount of token out
    * @return taxBaseIn The amount of tokenIn swapped when in shortage of tokenOut
    */
    function _calcOutGivenInMMMMixed(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal memory tokenGlobalOut,
        Struct.SwapParameters memory swapParameters,
        uint256 relativePrice,
        uint256 adjustedTokenWeightOut,
        uint256 balanceInAtEquilibrium
    )
    internal view
    returns (uint256, uint256)
    {

        uint256 tokenInSellAmountForEquilibrium = balanceInAtEquilibrium - tokenGlobalIn.info.balance;
        uint256 taxBaseIn = swapParameters.amount - tokenInSellAmountForEquilibrium;

        // 'abundance of tokenOut' phase --> no spread
        uint256 tokenAmountOutPart1 = _calcOutGivenInMMMAbundance(
            tokenGlobalIn,
            tokenGlobalOut,
            relativePrice,
            tokenInSellAmountForEquilibrium,
            swapParameters.fee,
            swapParameters.fallbackSpread
        );

        // 'shortage of tokenOut phase' --> apply spread
        uint256 tokenAmountOutPart2 = calcOutGivenIn(
            tokenGlobalIn.info.balance + tokenInSellAmountForEquilibrium,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance - tokenAmountOutPart1,
            adjustedTokenWeightOut,
            taxBaseIn, // tokenAmountIn > tokenInSellAmountForEquilibrium
            swapParameters.fee
        );

        return (tokenAmountOutPart1 + tokenAmountOutPart2, taxBaseIn);

    }

    /**
    * @notice Computes the amount of tokenIn needed in order to receive a given amount of tokenOut
    * @dev A spread is applied as soon as entering a "shortage of tokenOut" phase
    * cf whitepaper: https://www.swaap.finance/whitepaper.pdf
    * @param tokenGlobalIn The pool global information on tokenIn
    * @param tokenGlobalOut The pool global information on tokenOut
    * @param relativePrice The price of tokenOut in tokenIn terms
    * @param swapParameters Amount of token out and swap fee
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param hpParameters The parameters for historical prices retrieval
    * @return swapResult The swap result (amount in, spread and tax base in)
    */
    function calcInGivenOutMMM(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal memory tokenGlobalOut,
        uint256 relativePrice,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    public view
    returns (Struct.SwapResult memory)
    {

        // determines the balance of tokenOut at equilibrium (cf definitions)
        uint256 balanceOutAtEquilibrium = getTokenBalanceAtEquilibrium(
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            Num.div(Const.ONE, relativePrice)
        );

        // from abundance of tokenOut to abundance of tokenOut --> no spread
        if (tokenGlobalOut.info.balance > balanceOutAtEquilibrium && swapParameters.amount < tokenGlobalOut.info.balance - balanceOutAtEquilibrium) {
            return (
                Struct.SwapResult(
                    _calcInGivenOutMMMAbundance(
                        tokenGlobalIn, tokenGlobalOut,
                        relativePrice,
                        swapParameters.amount,
                        swapParameters.fee,
                        swapParameters.fallbackSpread
                    ),
                    0,
                    0
                )
            );
        }

        {
            Struct.GBMEstimation memory gbmEstimation = GeometricBrownianMotionOracle.getParametersEstimation(
                tokenGlobalIn.latestRound, tokenGlobalOut.latestRound,
                hpParameters
            );

            (uint256 adjustedTokenOutWeight, uint256 spread) = getMMMWeight(
                true,
                swapParameters.fallbackSpread,
                tokenGlobalOut.info.weight,
                gbmEstimation, gbmParameters
            );

            if (tokenGlobalOut.info.balance <= balanceOutAtEquilibrium) {
                // shortage to shortage
                return (
                    Struct.SwapResult(
                        calcInGivenOut(
                            tokenGlobalIn.info.balance,
                            tokenGlobalIn.info.weight,
                            tokenGlobalOut.info.balance,
                            adjustedTokenOutWeight,
                            swapParameters.amount,
                            swapParameters.fee
                        ),
                        spread,
                        swapParameters.amount
                    )
                );
            }
            else {
                // abundance to shortage
                (uint256 amount, uint256 taxBaseIn) = _calcInGivenOutMMMMixed(
                    tokenGlobalIn,
                    tokenGlobalOut,
                    swapParameters,
                    relativePrice,
                    adjustedTokenOutWeight,
                    balanceOutAtEquilibrium
                );
                return (
                    Struct.SwapResult(
                        amount,
                        spread,
                        taxBaseIn
                    )
                );
            }

        }

    }

    /**
    * @notice Implements calcOutGivenInMMM in the case of abundance of tokenOut
    * @dev A spread is applied as soon as entering a "shortage of tokenOut" phase
    * cf whitepaper: https://www.swaap.finance/whitepaper.pdf
    * @param tokenGlobalIn The pool global information on tokenIn
    * @param tokenGlobalOut The pool global information on tokenOut
    * @param relativePrice The price of tokenOut in tokenIn terms
    * @param tokenAmountOut The amount of tokenOut that will be received
    * @param baseFee The base fee
    * @param fallbackSpread The default spread in case the it couldn't be calculated using oracle prices
    * @return tokenAmountIn The amount of tokenIn needed for the swap
    */
    function _calcInGivenOutMMMAbundance(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal memory tokenGlobalOut,
        uint256 relativePrice,
        uint256 tokenAmountOut,
        uint256 baseFee,
        uint256 fallbackSpread
    ) public view returns (uint256) {
        uint256 adaptiveFees = getAdaptiveFees(
            tokenGlobalIn,
            Num.mul(tokenAmountOut, relativePrice),
            tokenGlobalOut,
            tokenAmountOut,
            relativePrice,
            baseFee,
            fallbackSpread
        );
        return (
            calcInGivenOut(
                tokenGlobalIn.info.balance,
                tokenGlobalIn.info.weight,
                tokenGlobalOut.info.balance,
                tokenGlobalOut.info.weight,
                tokenAmountOut,
                adaptiveFees
            )
        );
    }

    /**
    * @notice Implements 'calcInGivenOutMMM' in the case of abundance of tokenOut
    * @dev Two cases to consider:
    * 1) amount of tokenIn won't drive the pool from abundance of tokenOut to shortage ==> 1 pricing (no spread)
    * 2) amount of tokenIn will drive the pool from abundance of tokenOut to shortage ==> 2 pricing, one for each phase
    * @param tokenGlobalIn The pool global information on tokenIn
    * @param tokenGlobalOut The pool global information on tokenOut
    * @param swapParameters The parameters of the swap
    * @param relativePrice The price of tokenOut in tokenIn terms
    * @param adjustedTokenWeightOut The spread-augmented tokenOut's weight
    * @return tokenAmountIn The total amount of tokenIn needed for the swap
    * @return taxBaseIn The amount of tokenIn swapped when in shortage of tokenOut
    */
    function _calcInGivenOutMMMMixed(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal memory tokenGlobalOut,
        Struct.SwapParameters memory swapParameters,
        uint256 relativePrice,
        uint256 adjustedTokenWeightOut,
        uint256 balanceOutAtEquilibrium
    )
    internal view
    returns (uint256, uint256)
    {
        
        uint256 tokenOutBuyAmountForEquilibrium =  tokenGlobalOut.info.balance - balanceOutAtEquilibrium;

        // 'abundance of tokenOut' phase --> no spread
        uint256 tokenAmountInPart1 = _calcInGivenOutMMMAbundance(
            tokenGlobalIn,
            tokenGlobalOut,
            relativePrice,
            tokenOutBuyAmountForEquilibrium,
            swapParameters.fee,
            swapParameters.fallbackSpread
        );

        // 'shortage of tokenOut phase' --> apply spread
        uint256 tokenAmountInPart2 = calcInGivenOut(
            tokenGlobalIn.info.balance + tokenAmountInPart1,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance - tokenOutBuyAmountForEquilibrium,
            adjustedTokenWeightOut,
            swapParameters.amount - tokenOutBuyAmountForEquilibrium, // tokenAmountOut > tokenOutBuyAmountForEquilibrium
            swapParameters.fee
        );

        return (tokenAmountInPart1 + tokenAmountInPart2, tokenAmountInPart2);
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
    * @param relativePrice The price of tokenOut in tokenIn terms
    * @return balance1AtEquilibrium The balance of token1 in order to have a token1/token2 at equilibrium
    */
    function getTokenBalanceAtEquilibrium( 
        uint256 tokenBalance1,
        uint256 tokenWeight1,
        uint256 tokenBalance2,
        uint256 tokenWeight2,
        uint256 relativePrice
    )
    public pure
    returns (uint256 balance1AtEquilibrium)
    {
        {
            uint256 weightSum = tokenWeight1 + tokenWeight2;
            // relativePrice * weight1/weight2
            uint256 foo = Num.mul(relativePrice, Num.div(tokenWeight1, tokenWeight2));
            // relativePrice * balance2 * (weight1/weight2)
            foo = Num.mul(foo, tokenBalance2);
            
            balance1AtEquilibrium = Num.mul(
                LogExpMath.pow(
                    foo,
                    Num.div(tokenWeight2, weightSum)
                ),
                LogExpMath.pow(
                    tokenBalance1,
                    Num.div(tokenWeight1, weightSum)
                )
            );
        }
        return balance1AtEquilibrium;

    }

    /**
    * @notice Computes the fee needed to maintain the pool's value constant
    * @dev We use oracle to evaluate pool's value
    * @param tokenBalanceIn The balance of tokenIn initially
    * @param tokenAmountIn The amount of tokenIn to be added
    * @param tokenWeightIn The weight of tokenIn
    * @param tokenBalanceOut The balance of tokenOut initially
    * @param tokenAmountOut The amount of tokenOut to be removed from the pool
    * @param tokenWeightOut The weight of tokenOut
    * @return adaptiveFee The computed adaptive fee to be added to the base fees
    */
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
        uint256 weightRatio = Num.div(tokenWeightOut, tokenWeightIn);
        uint256 y = Num.div(tokenBalanceOut, tokenBalanceOut - tokenAmountOut);
        uint256 foo = Num.mul(tokenBalanceIn, Num.pow(y, weightRatio));

        uint256 afterSwapTokenInBalance = tokenBalanceIn + tokenAmountIn;

        // equivalent to max(0, (foo - afterSwapTokenInBalance / -tokenAmountIn)
        if (foo > afterSwapTokenInBalance) {
            return 0;
        }
        return (
            Num.div(
                afterSwapTokenInBalance - foo,
                tokenAmountIn
            )
        );
    }

    /**
    * @notice Computes the fee amount that will ensure we maintain the pool's value, according to oracle prices.
    * @dev We apply this fee regime only if Out-In price increased in the same block as now.
    * @param tokenGlobalIn The pool global information on tokenIn
    * @param tokenAmountIn The swap desired amount for tokenIn
    * @param tokenGlobalOut The pool global information on tokenOut
    * @param tokenAmountOut The swap desired amount for tokenOut
    * @param relativePrice The price of tokenOut in tokenIn terms
    * @param baseFee The base fee amount
    * @param fallbackSpread The default spread in case the it couldn't be calculated using oracle prices
    * @return alpha The potentially augmented fee amount
    */
    function getAdaptiveFees(
        Struct.TokenGlobal memory tokenGlobalIn,
        uint256 tokenAmountIn,
        Struct.TokenGlobal memory tokenGlobalOut,
        uint256 tokenAmountOut,
        uint256 relativePrice,
        uint256 baseFee,
        uint256 fallbackSpread
    ) internal view returns (uint256 alpha) {

        // we only consider same block as last price update
        if ((block.timestamp != tokenGlobalIn.latestRound.timestamp && block.timestamp != tokenGlobalOut.latestRound.timestamp)) {
            // no additional fees
            return alpha = baseFee;
        }
        uint256 recentPriceUpperBound = ChainlinkUtils.getMaxRelativePriceInLastBlock(
            tokenGlobalIn.latestRound,
            tokenGlobalIn.info.decimals,
            tokenGlobalOut.latestRound,
            tokenGlobalOut.info.decimals
        );
        if (recentPriceUpperBound == 0) {
            // we were not able to retrieve the previous price
            return alpha = fallbackSpread;
        } else if (recentPriceUpperBound <= relativePrice) {
            // no additional fees
            return alpha = baseFee;
        }

        return (
            // additional fees indexed on price increase and imbalance
            alpha = baseFee + calcAdaptiveFeeGivenInAndOut(
                tokenGlobalIn.info.balance,
                tokenAmountIn,
                tokenGlobalIn.info.weight,
                tokenGlobalOut.info.balance,
                tokenAmountOut,
                tokenGlobalOut.info.weight
            )
        );

    }

    /**
    * @notice Computes the adaptive fees when joining a pool
    * @dev Adaptive fees are the fees related to the price increase of tokenIn with respect to tokenOut
    * reported by the oracles in the same block as the transaction
    * @param poolValueInTokenIn The pool value in terms of tokenIn
    * @param tokenBalanceIn The pool's balance of tokenIn
    * @param normalizedTokenWeightIn The normalized weight of tokenIn
    * @param tokenAmountIn The amount of tokenIn to be swapped
    * @return adaptiveFees The adaptive fees (should be added to the pool's swap fees)
    */
    function calcPoolOutGivenSingleInAdaptiveFees(
        uint256 poolValueInTokenIn,
        uint256 tokenBalanceIn,
        uint256 normalizedTokenWeightIn,
        uint256 tokenAmountIn
    ) internal pure returns (uint256) {
        uint256 foo = Num.mul(
            Num.div(tokenBalanceIn, tokenAmountIn),
            Num.pow(
                Num.div(
                    poolValueInTokenIn + tokenAmountIn,
                    poolValueInTokenIn
                ),
                Num.div(Const.ONE, normalizedTokenWeightIn)
            ) - Const.ONE
        );
        if (foo >= Const.ONE) {
            return 0;
        }
        return (
            Num.div(
                Const.ONE - foo,
                Const.ONE - normalizedTokenWeightIn
            )
        );
    }

    /**
    * @notice Computes the adaptive fees when exiting a pool
    * @dev Adaptive fees are the fees related to the price increase of tokenIn with respect to tokenOut
    * reported by the oracles in the same block as the transaction
    * @param poolValueInTokenOut The pool value in terms of tokenOut
    * @param tokenBalanceOut The pool's balance of tokenOut
    * @param normalizedTokenWeightOut The normalized weight of tokenOut
    * @param normalizedPoolAmountOut The normalized amount of pool token's to be burned
    * @return adaptiveFees The adaptive fees (should be added to the pool's swap fees)
    */
    function calcSingleOutGivenPoolInAdaptiveFees(
        uint256 poolValueInTokenOut,
        uint256 tokenBalanceOut,
        uint256 normalizedTokenWeightOut,
        uint256 normalizedPoolAmountOut
    ) internal pure returns (uint256) {
        uint256 foo = Num.div(
            Num.mul(poolValueInTokenOut, normalizedPoolAmountOut),
            Num.mul(
                tokenBalanceOut,
                    Const.ONE -
                    Num.pow(
                        Const.ONE - normalizedPoolAmountOut,
                        Num.div(Const.ONE, normalizedTokenWeightOut)
                    )
            )
        );
        if (foo >= Const.ONE) {
            return 0;
        }
        return (
        Num.div(
            Const.ONE - foo,
            Const.ONE - normalizedTokenWeightOut
        )
        );
    }

    /**
    * @notice Computes the total value of the pool in terms of the quote token
    */
    function getPoolTotalValue(Struct.TokenGlobal memory quoteToken, Struct.TokenGlobal[] memory baseTokens)
    internal pure returns (uint256 basesTotalValue){
        basesTotalValue = quoteToken.info.balance;
        for (uint256 i; i < baseTokens.length;) {
            basesTotalValue += Num.mul(
                baseTokens[i].info.balance,
                ChainlinkUtils.getTokenRelativePrice(
                    quoteToken.latestRound.price,
                    quoteToken.info.decimals,
                    baseTokens[i].latestRound.price,
                    baseTokens[i].info.decimals
                )
            );
            unchecked { ++i; }
        }
        return basesTotalValue;
    }

}
