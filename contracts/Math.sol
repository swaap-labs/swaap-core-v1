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
    public pure
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
        public pure
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

    /**********************************************************************************************
    // calcPoolOutGivenSingleIn                                                                  //
    // pAo = poolAmountOut         /                                              \              //
    // tAi = tokenAmountIn        ///      /     //    wI \      \\       \     wI \             //
    // wI = tokenWeightIn        //| tAi *| 1 - || 1 - --  | * sF || + tBi \    --  \            //
    // tW = totalWeight     pAo=||  \      \     \\    tW /      //         | ^ tW   | * pS - pS //
    // tBi = tokenBalanceIn      \\  ------------------------------------- /        /            //
    // pS = poolSupply            \\                    tBi               /        /             //
    // sF = swapFee                \                                              /              //
    **********************************************************************************************/
    function calcPoolOutGivenSingleIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountIn,
        uint swapFee
    )
        public pure
        returns (uint poolAmountOut)
    {
        // Charge the trading fee for the proportion of tokenAi
        //  which is implicitly traded to the other pool tokens.
        // That proportion is (1- weightTokenIn)
        // tokenAiAfterFee = tAi * (1 - (1-weightTi) * poolFee);
        uint normalizedWeight = Num.bdiv(tokenWeightIn, totalWeight);
        uint zaz = Num.bmul(Const.BONE - normalizedWeight, swapFee); 
        uint tokenAmountInAfterFee = Num.bmul(tokenAmountIn, Const.BONE - zaz);

        uint newTokenBalanceIn = tokenBalanceIn + tokenAmountInAfterFee;
        uint tokenInRatio = Num.bdiv(newTokenBalanceIn, tokenBalanceIn);

        // uint newPoolSupply = (ratioTi ^ weightTi) * poolSupply;
        uint poolRatio = Num.bpow(tokenInRatio, normalizedWeight);
        uint newPoolSupply = Num.bmul(poolRatio, poolSupply);
        poolAmountOut = newPoolSupply - poolSupply;
        return poolAmountOut;
    }

    function calcPoolOutGivenSingleInMMM(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal[] memory tokensGlobalOut,
        Struct.JoinExitSwapParameters memory joinexitswapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
        public view
        returns (uint poolAmountOut)
    {

        // to get the total adjusted weight, we assume all the tokens Out are in shortage
        uint totalAdjustedWeight = getTotalWeightMMM(
            true,
            joinexitswapParameters.fallbackSpread,
            tokenGlobalIn,
            tokensGlobalOut,
            gbmParameters,
            hpParameters
        );

        uint256 fee = joinexitswapParameters.fee;

        bool blockHasPriceUpdate = block.timestamp == tokenGlobalIn.latestRound.timestamp;
        {
            uint8 i;
            while ((!blockHasPriceUpdate) && (i < tokensGlobalOut.length)) {
                if (block.timestamp == tokensGlobalOut[i].latestRound.timestamp) {
                    blockHasPriceUpdate = true;
                }
                unchecked { ++i; }
            }
        }
        if (blockHasPriceUpdate) {
            uint256 poolValueInTokenIn = tokenGlobalIn.info.balance + getBasesTotalValue(tokenGlobalIn, tokensGlobalOut);
            fee += calcPoolOutGivenSingleInAdaptiveFees(
                poolValueInTokenIn,
                tokenGlobalIn.info.balance,
                Num.bdiv(tokenGlobalIn.info.weight, totalAdjustedWeight),
                joinexitswapParameters.amount
            );
        }

        poolAmountOut = calcPoolOutGivenSingleIn(
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            joinexitswapParameters.poolSupply,
            totalAdjustedWeight,
            joinexitswapParameters.amount,
            fee
        );

        return poolAmountOut;
    }

    /**********************************************************************************************
    // calcSingleOutGivenPoolIn                                                                  //
    // tAo = tokenAmountOut            /      /                                             \\   //
    // bO = tokenBalanceOut           /      // pS - (pAi * (1 - eF)) \     /    1    \      \\  //
    // pAi = poolAmountIn            | bO - || ----------------------- | ^ | --------- | * b0 || //
    // ps = poolSupply                \      \\          pS           /     \(wO / tW)/      //  //
    // wI = tokenWeightIn      tAo =   \      \                                             //   //
    // tW = totalWeight                    /     /      wO \       \                             //
    // sF = swapFee                    *  | 1 - |  1 - ---- | * sF  |                            //
    // eF = exitFee                        \     \      tW /       /                             //
    **********************************************************************************************/
    function calcSingleOutGivenPoolIn(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountIn,
        uint swapFee
    )
    public pure
    returns (uint tokenAmountOut)
    {
        uint normalizedWeight = Num.bdiv(tokenWeightOut, totalWeight);
        // charge exit fee on the pool token side
        // pAiAfterExitFee = pAi*(1-exitFee)
        uint poolAmountInAfterExitFee = Num.bmul(poolAmountIn, Const.BONE - Const.EXIT_FEE);
        uint newPoolSupply = poolSupply - poolAmountInAfterExitFee;
        uint poolRatio = Num.bdiv(newPoolSupply, poolSupply);

        // newBalTo = poolRatio^(1/weightTo) * balTo;
        uint tokenOutRatio = Num.bpow(poolRatio, Num.bdiv(Const.BONE, normalizedWeight));
        uint newTokenBalanceOut = Num.bmul(tokenOutRatio, tokenBalanceOut);

        uint tokenAmountOutBeforeSwapFee = tokenBalanceOut - newTokenBalanceOut;

        // charge swap fee on the output token side
        //uint tAo = tAoBeforeSwapFee * (1 - (1-weightTo) * swapFee)
        uint zaz = Num.bmul(Const.BONE - normalizedWeight, swapFee);
        tokenAmountOut = Num.bmul(tokenAmountOutBeforeSwapFee, Const.BONE - zaz);
        return tokenAmountOut;
    }

    function calcSingleOutGivenPoolInMMM(
        Struct.TokenGlobal memory tokenGlobalOut,
        Struct.TokenGlobal[] memory remainingTokens,
        Struct.JoinExitSwapParameters memory joinexitswapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    public view
    returns (uint tokenAmountOut)
    {
        // to get the total adjusted weight, we assume all the remaining tokens are in shortage
        uint totalAdjustedWeight = getTotalWeightMMM(
            false,
            joinexitswapParameters.fallbackSpread,
            tokenGlobalOut,
            remainingTokens,
            gbmParameters,
            hpParameters
        );

        uint256 fee = joinexitswapParameters.fee;

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
            uint256 poolValueInTokenOut = tokenGlobalOut.info.balance + getBasesTotalValue(tokenGlobalOut, remainingTokens);
            fee += calcSingleOutGivenPoolInAdaptiveFees(
                poolValueInTokenOut,
                tokenGlobalOut.info.balance,
                Num.bdiv(tokenGlobalOut.info.weight, totalAdjustedWeight),
                Num.bdiv(joinexitswapParameters.amount, joinexitswapParameters.poolSupply)
            );
        }

        tokenAmountOut = calcSingleOutGivenPoolIn(
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            joinexitswapParameters.poolSupply,
            totalAdjustedWeight,
            joinexitswapParameters.amount,
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
            mean = -int256(Num.bmul(uint256(-mean), horizon));
        } else {
            mean = int256(Num.bmul(uint256(mean), horizon));
        }
        uint256 diffusion;
        if (variance > 0) {
            diffusion = Num.bmul(
                z,
                LogExpMath.pow(
                    Num.bmul(variance, 2 * horizon),
                    Const.BONE / 2
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
    * @return the modified tokenWeightOut and its corresponding spread
    */
    function getMMMWeight(
        bool shortage,
        uint256 fallbackSpread,
        uint256 tokenWeight,
        Struct.GBMEstimation memory gbmEstimation,
        Struct.GBMParameters memory gbmParameters
    )
    public pure
    returns (uint256, uint256)
    {

        if (!gbmEstimation.success) {
            if (shortage) {
                return (Num.bmul(tokenWeight, Const.BONE + fallbackSpread), fallbackSpread);
            } else {
                return (Num.bdiv(tokenWeight, Const.BONE + fallbackSpread), fallbackSpread);
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
        if (spreadFactor <= Const.BONE) {
            return (tokenWeight, 0);
        }

        uint256 spread = spreadFactor - Const.BONE;

        if (shortage) {
            return (Num.bmul(tokenWeight, spreadFactor), spread);
        } else {
            return (Num.bdiv(tokenWeight, spreadFactor), spread);
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
    returns (uint totalAdjustedWeight)
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
        for (uint i; i < otherTokens.length;) {

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
    * @return The swap execution conditions
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
    returns (Struct.SwapResult memory)
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
    * @return The rate in tokenOut terms for tokenAmountIn of tokenIn
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
            Num.bdiv(tokenAmountIn, relativePrice),
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
    * @return tokenAmountOut The swap execution conditions
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
    * @return The swap execution conditions
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
            Num.bdiv(Const.BONE, relativePrice)
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
    * @return The rate in tokenOut terms for tokenAmountIn of tokenIn
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
            Num.bmul(tokenAmountOut, relativePrice),
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
    * @return tokenAmountIn TokenIn Amount needed for the swap 
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
            uint256 foo = Num.bmul(relativePrice, Num.bdiv(tokenWeight1, tokenWeight2));
            // relativePrice * balance2 * (weight1/weight2)
            foo = Num.bmul(foo, tokenBalance2);
            
            balance1AtEquilibrium = Num.bmul(
                LogExpMath.pow(
                    foo,
                    Num.bdiv(tokenWeight2, weightSum)
                ),
                LogExpMath.pow(
                    tokenBalance1,
                    Num.bdiv(tokenWeight1, weightSum)
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
        uint weightRatio = Num.bdiv(tokenWeightOut, tokenWeightIn);
        uint y = Num.bdiv(tokenBalanceOut, tokenBalanceOut - tokenAmountOut);
        uint foo = Num.bmul(tokenBalanceIn, Num.bpow(y, weightRatio));

        uint256 afterSwapTokenInBalance = tokenBalanceIn + tokenAmountIn;

        // equivalent to max(0, (foo - afterSwapTokenInBalance / -tokenAmountIn)
        if (foo > afterSwapTokenInBalance) {
            return 0;
        }
        return (
            Num.bdiv(
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

    function calcPoolOutGivenSingleInAdaptiveFees(
        uint256 poolValueInTokenIn,
        uint256 tokenBalanceIn,
        uint256 normalizedTokenWeightIn,
        uint256 tokenAmountIn
    ) internal pure returns (uint256) {
        uint256 foo = Num.bmul(
            Num.bdiv(tokenBalanceIn, tokenAmountIn),
            Num.bpow(
                Num.bdiv(
                    poolValueInTokenIn + tokenAmountIn,
                    poolValueInTokenIn
                ),
                Num.bdiv(Const.BONE, normalizedTokenWeightIn)
            ) - Const.BONE
        );
        if (foo >= Const.BONE) {
            return 0;
        }
        return (
            Num.bdiv(
                Const.BONE - foo,
                Const.BONE - normalizedTokenWeightIn
            )
        );
    }

    function calcSingleOutGivenPoolInAdaptiveFees(
        uint256 poolValueInTokenOut,
        uint256 tokenBalanceOut,
        uint256 normalizedTokenWeightOut,
        uint256 normalizedPoolAmountOut
    ) internal pure returns (uint256) {
        uint256 foo = Num.bdiv(
            Num.bmul(poolValueInTokenOut, normalizedPoolAmountOut),
            Num.bmul(
                tokenBalanceOut,
                    Const.BONE -
                    Num.bpow(
                        Const.BONE - normalizedPoolAmountOut,
                        Num.bdiv(Const.BONE, normalizedTokenWeightOut)
                    )
            )
        );
        if (foo >= Const.BONE) {
            return 0;
        }
        return (
        Num.bdiv(
            Const.BONE - foo,
            Const.BONE - normalizedTokenWeightOut
        )
        );
    }

    function getBasesTotalValue(Struct.TokenGlobal memory quoteToken, Struct.TokenGlobal[] memory baseTokens)
    internal pure returns (uint256 basesTotalValue){
        for (uint i; i < baseTokens.length;) {
            basesTotalValue += Num.bmul(
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
