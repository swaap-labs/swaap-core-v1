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
        uint poolSupply,
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal[] memory tokensGlobalOut,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
        public view
        returns (uint poolAmountOut)
    {

        // to get the total adjusted weight, we assume all the tokens Out are in shortage
        uint totalAdjustedWeight = getTotalWeightMMM(
            true,
            swapParameters.fallbackSpread,
            tokenGlobalIn,
            tokensGlobalOut,
            gbmParameters,
            hpParameters
        );

        poolAmountOut = calcPoolOutGivenSingleIn(
        tokenGlobalIn.info.balance,
        tokenGlobalIn.info.weight,
        poolSupply,
        totalAdjustedWeight,
        swapParameters.amount,
        swapParameters.fee
        );

        return poolAmountOut;
    }

    /**********************************************************************************************
    // calcSingleInGivenPoolOut                                                                  //
    // tAi = tokenAmountIn              //(pS + pAo)\     /    1    \\                           //
    // pS = poolSupply                 || ---------  | ^ | --------- || * bI - bI                //
    // pAo = poolAmountOut              \\    pS    /     \(wI / tW)//                           //
    // bI = balanceIn          tAi =  --------------------------------------------               //
    // wI = weightIn                              /      wI  \                                   //
    // tW = totalWeight                          |  1 - ----  |  * sF                            //
    // sF = swapFee                               \      tW  /                                   //
    **********************************************************************************************/
    function calcSingleInGivenPoolOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountOut,
        uint swapFee
    )
        public pure
        returns (uint tokenAmountIn)
    {
        uint normalizedWeight = Num.bdiv(tokenWeightIn, totalWeight);
        uint newPoolSupply = poolSupply + poolAmountOut;
        uint poolRatio = Num.bdiv(newPoolSupply, poolSupply);
      
        //uint newBalTi = poolRatio^(1/weightTi) * balTi;
        uint boo = Num.bdiv(Const.BONE, normalizedWeight); 
        uint tokenInRatio = Num.bpow(poolRatio, boo);
        uint newTokenBalanceIn = Num.bmul(tokenInRatio, tokenBalanceIn);
        uint tokenAmountInAfterFee = newTokenBalanceIn - tokenBalanceIn;
        // Do reverse order of fees charged in joinswap_ExternAmountIn, this way 
        //     ``` pAo == joinswap_ExternAmountIn(Ti, joinswap_PoolAmountOut(pAo, Ti)) ```
        //uint tAi = tAiAfterFee / (1 - (1-weightTi) * swapFee) ;
        uint zar = Num.bmul(Const.BONE - normalizedWeight, swapFee);
        tokenAmountIn = Num.bdiv(tokenAmountInAfterFee, Const.BONE - zar);
        return tokenAmountIn;
    }

    function calcSingleInGivenPoolOutMMM(
        uint poolSupply,
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal[] memory tokensGlobalOut,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
        public view
        returns (uint tokenAmountIn)
    {

        // to get the total adjusted weight, we assume all the tokens Out are in shortage
        uint totalAdjustedWeight = getTotalWeightMMM(
            true,
            swapParameters.fallbackSpread,
            tokenGlobalIn,
            tokensGlobalOut,
            gbmParameters,
            hpParameters
        );

        tokenAmountIn = calcSingleInGivenPoolOut(
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            poolSupply,
            totalAdjustedWeight,
            swapParameters.amount,
            swapParameters.fee
        );

        return tokenAmountIn;
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
        uint poolSupply,
        Struct.TokenGlobal memory tokenGlobalOut,
        Struct.TokenGlobal[] memory remainingTokens,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
        public view
        returns (uint tokenAmountOut)
    {
        // to get the total adjusted weight, we assume all the remaining tokens are in shortage
        uint totalAdjustedWeight = getTotalWeightMMM(
            false,
            swapParameters.fallbackSpread,
            tokenGlobalOut,
            remainingTokens,
            gbmParameters,
            hpParameters
        );

        tokenAmountOut = calcSingleOutGivenPoolIn(
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            poolSupply,
            totalAdjustedWeight,
            swapParameters.amount,
            swapParameters.fee
        );

        return tokenAmountOut;
    }

    /**********************************************************************************************
    // calcPoolInGivenSingleOut                                                                  //
    // pAi = poolAmountIn               // /               tAo             \\     / wO \     \   //
    // bO = tokenBalanceOut            // | bO - -------------------------- |\   | ---- |     \  //
    // tAo = tokenAmountOut      pS - ||   \     1 - ((1 - (tO / tW)) * sF)/  | ^ \ tW /  * pS | //
    // ps = poolSupply                 \\ -----------------------------------/                /  //
    // wO = tokenWeightOut  pAi =       \\               bO                 /                /   //
    // tW = totalWeight           -------------------------------------------------------------  //
    // sF = swapFee                                        ( 1 - eF )                            //
    // eF = exitFee                                                                              //
    **********************************************************************************************/
    function calcPoolInGivenSingleOut(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountOut,
        uint swapFee
    )
        public pure
        returns (uint poolAmountIn)
    {

        // charge swap fee on the output token side 
        uint normalizedWeight = Num.bdiv(tokenWeightOut, totalWeight);
        //uint tAoBeforeSwapFee = tAo / (1 - (1-weightTo) * swapFee) ;
        uint zoo = Const.BONE - normalizedWeight;
        uint zar = Num.bmul(zoo, swapFee); 
        uint tokenAmountOutBeforeSwapFee = Num.bdiv(tokenAmountOut, Const.BONE - zar);

        uint newTokenBalanceOut = tokenBalanceOut - tokenAmountOutBeforeSwapFee;
        uint tokenOutRatio = Num.bdiv(newTokenBalanceOut, tokenBalanceOut);

        //uint newPoolSupply = (ratioTo ^ weightTo) * poolSupply;
        uint poolRatio = Num.bpow(tokenOutRatio, normalizedWeight);
        uint newPoolSupply = Num.bmul(poolRatio, poolSupply);
        uint poolAmountInAfterExitFee = poolSupply - newPoolSupply;

        // charge exit fee on the pool token side
        // pAi = pAiAfterExitFee/(1-exitFee)
        poolAmountIn = Num.bdiv(poolAmountInAfterExitFee, Const.BONE - Const.EXIT_FEE);
        return poolAmountIn;
    }

    function calcPoolInGivenSingleOutMMM(
        uint poolSupply,
        Struct.TokenGlobal memory tokenGlobalOut,
        Struct.TokenGlobal[] memory remainingTokens,
        Struct.SwapParameters memory swapParameters,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
        public view
        returns (uint tokenAmountOut)
    {
        // to get the total adjusted weight, we assume all the remaining tokens are in shortage
        uint totalAdjustedWeight = getTotalWeightMMM(
            false,
            swapParameters.fallbackSpread,
            tokenGlobalOut,
            remainingTokens,
            gbmParameters,
            hpParameters
        );

        tokenAmountOut = calcPoolInGivenSingleOut(
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            poolSupply,
            totalAdjustedWeight,
            swapParameters.amount,
            swapParameters.fee
        );

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
    * @param tokenGlobalIn The pool global information on tokenIn
    * @param tokenGlobalOut The pool global information on tokenOut
    * @param relativePrice The price of tokenOut in tokenIn terms
    * @param fallbackSpread The default spread in case the it couldn't be calculated using oracle prices
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param hpParameters The parameters for historical prices retrieval
    * @return spotPriceMMM The spot price of tokenOut in tokenIn terms
    */
    function calcSpotPriceMMM(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal memory tokenGlobalOut,
        uint256 relativePrice,
        uint256 swapFee,
        uint256 fallbackSpread,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    )
    public view
    returns (uint256 spotPriceMMM)
    {
        {

            // if tokenOut is in shortage --> apply spread
            if (tokenGlobalIn.info.balance >= getTokenBalanceAtEquilibrium(
                tokenGlobalIn.info.balance,
                tokenGlobalIn.info.weight,
                tokenGlobalOut.info.balance,
                tokenGlobalOut.info.weight,
                relativePrice
            )) {

                Struct.GBMEstimation memory gbmEstimation = GeometricBrownianMotionOracle.getParametersEstimation(
                    tokenGlobalIn.latestRound,
                    tokenGlobalOut.latestRound,
                    hpParameters
                );

                (uint256 adjustedWeightOut, ) = getMMMWeight(true, fallbackSpread, tokenGlobalOut.info.weight, gbmEstimation, gbmParameters);
                return (
                    spotPriceMMM = calcSpotPrice(
                        tokenGlobalIn.info.balance,
                        tokenGlobalIn.info.weight,
                        tokenGlobalOut.info.balance,
                        adjustedWeightOut,
                        swapFee
                    )
                );
            }
        }

        // if tokenOut is in abundance --> no spread
        return (
            spotPriceMMM = calcSpotPrice(
                tokenGlobalIn.info.balance,
                tokenGlobalIn.info.weight,
                tokenGlobalOut.info.balance,
                tokenGlobalOut.info.weight,
                swapFee
            )
        );
    }

    /**
    * @notice Computes the log spread factor
    * @dev We define it as the quantile of a GBM process (log-normal distribution)
    * which represents the traded pair process.
    * given by the following: exponential(mean * horizon + z * sqrt(variance * 2 * horizon)
    * where z is the complementary error function (erfc)
    * GBM: https://en.wikipedia.org/wiki/Geometric_Brownian_motion
    * log normal: https://en.wikipedia.org/wiki/Log-normal_distribution
    * erfc: https://en.wikipedia.org/wiki/Complementary_error_function
    * @param mean The GBM's mean
    * @param variance The GBM's variance
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
    * @notice Computes the total denormalized weight assuming that all the tokensOut are in shortage or in abundance 
    * @dev The initial weights of the tokens are the ones adjusted by their price performance only
    * @param shortage True if tokenOut is in shortage
    * @param fallbackSpread The default spread in case the it couldn't be calculated using oracle prices
    * @param tokenGlobalIn The tokenIn's global information (token records + latest round info)
    * @param tokensGlobalOut All the tokenOuts' global information (token records + latest rounds info)
    * @param gbmParameters The GBM forecast parameters (Z, horizon)
    * @param hpParameters The parameters for historical prices retrieval
    * @return totalAdjustedWeight The total adjusted weight where tokens out are only in shortage
    */
    function getTotalWeightMMM(
        bool shortage,
        uint256 fallbackSpread,
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal[] memory tokensGlobalOut,
        Struct.GBMParameters memory gbmParameters,
        Struct.HistoricalPricesParameters memory hpParameters
    ) 
        internal view 
        returns (uint totalAdjustedWeight)
    {
        
        bool noMoreDataPointIn;
        Struct.HistoricalPricesData memory hpDataIn;

        {   
            uint256[] memory pricesIn;
            uint256[] memory timestampsIn;
            uint256 startIndexIn;
            // retrieve historical prices of tokenIn
            (pricesIn,
             timestampsIn,
             startIndexIn,
             noMoreDataPointIn) = GeometricBrownianMotionOracle.getHistoricalPrices(tokenGlobalIn.latestRound, hpParameters);

            hpDataIn = Struct.HistoricalPricesData(startIndexIn, timestampsIn, pricesIn);

            // reducing lookback time window    
            uint256 reducedLookbackInSecCandidate = hpParameters.timestamp - timestampsIn[startIndexIn];
            if (reducedLookbackInSecCandidate < hpParameters.lookbackInSec) {
                hpParameters.lookbackInSec = reducedLookbackInSecCandidate;
            }   
        }

        // to get the total adjusted weight, we assume all the tokens Out are in shortage
        totalAdjustedWeight = tokenGlobalIn.info.weight;
        for (uint i; i < tokensGlobalOut.length;) {

            (uint256[] memory pricesOut,
            uint256[] memory timestampsOut,
            uint256 startIndexOut,
            bool noMoreDataPointOut) = GeometricBrownianMotionOracle.getHistoricalPrices(tokensGlobalOut[i].latestRound, hpParameters);
        
            Struct.GBMEstimation memory gbmEstimation = GeometricBrownianMotionOracle._getParametersEstimation(
                    noMoreDataPointIn && noMoreDataPointOut,
                    hpDataIn,
                    Struct.HistoricalPricesData(startIndexOut, timestampsOut, pricesOut),
                    hpParameters
            );
            
            (tokensGlobalOut[i].info.weight, ) = getMMMWeight(
                shortage,
                fallbackSpread,
                tokensGlobalOut[i].info.weight,
                gbmEstimation,
                gbmParameters
            );

            totalAdjustedWeight += tokensGlobalOut[i].info.weight;
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
                        spread
                    )
                );
            }
            else {
                // abundance to shortage
                return (
                    Struct.SwapResult(
                        _calcOutGivenInMMMMixed(
                            tokenGlobalIn,
                            tokenGlobalOut,
                            swapParameters,
                            relativePrice,
                            adjustedTokenOutWeight,
                            balanceInAtEquilibrium
                        ),
                        spread // TODO: broadcast necessary data to compute accurate fee revenue
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
    returns (uint256 tokenAmountOut)
    {

        uint256 tokenInSellAmountForEquilibrium = balanceInAtEquilibrium - tokenGlobalIn.info.balance;

        uint256 tokenAmountOutPart1 = _calcOutGivenInMMMAbundance(
            tokenGlobalIn,
            tokenGlobalOut,
            relativePrice,
            tokenInSellAmountForEquilibrium,
            swapParameters.fee,
            swapParameters.fallbackSpread
        );

        // 'shortage of tokenOut phase' --> apply spread
        return (
            tokenAmountOut = tokenAmountOutPart1 + calcOutGivenIn(
                tokenGlobalIn.info.balance + tokenInSellAmountForEquilibrium,
                tokenGlobalIn.info.weight,
                tokenGlobalOut.info.balance - tokenAmountOutPart1,
                adjustedTokenWeightOut,
                swapParameters.amount - tokenInSellAmountForEquilibrium, // tokenAmountIn > tokenInSellAmountForEquilibrium
                swapParameters.fee
            )
        );

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
                        spread
                    )
                );
            }
            else {
                // abundance to shortage
                return (
                    Struct.SwapResult(
                        _calcInGivenOutMMMMixed(
                            tokenGlobalIn,
                            tokenGlobalOut,
                            swapParameters,
                            relativePrice,
                            adjustedTokenOutWeight,
                            balanceOutAtEquilibrium
                        ),
                        spread // TODO: broadcast necessary data to compute accurate fee revenue
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
    returns (uint256 tokenAmountIn)
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
        uint256 previousPrice = ChainlinkUtils.getPreviousPrice(
            tokenGlobalIn.latestRound, tokenGlobalOut.latestRound
        );
        if (previousPrice == 0) {
            // we were not able to retrieve the previous price
            return alpha = fallbackSpread;
        } else if (previousPrice > relativePrice) {
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

}
