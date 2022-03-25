const Decimal = require('decimal.js');
const truffleAssert = require('truffle-assertions');
const { calcRelativeDiff } = require('../lib/calc_comparisons');

const Pool = artifacts.require('Pool');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');
const TConstantOracle = artifacts.require('TConstantOracle');

const errorDelta = 10 ** -8;
const swapFee = 0.001; // 0.001;
const exitFee = 0;
const verbose = process.env.VERBOSE;


contract('Pool', async (accounts) => {

	const now = 1641893000;

    const admin = accounts[0];
    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const MAX = web3.utils.toTwosComplement(-1);

    let WETH; let DAI;
    let weth; let dai;
    let factory; // Pool factory
    let pool; // first pool w/ defaults
    let POOL; //   pool address

    let wethOracle;
    let daiOracle;

    const wethBalance = '1000';
    const wethDenorm = '1';

    let currentWethBalance = Decimal(wethBalance);
    let previousWethBalance = currentWethBalance;

    const daiBalance = '1000';
    const daiDenorm = '49';

    let currentDaiBalance = Decimal(daiBalance);
    let previousDaiBalance = currentDaiBalance;

    let currentPoolBalance = Decimal(0);
    let previousPoolBalance = Decimal(0);

    const sumWeights = Decimal(wethDenorm).add(Decimal(daiDenorm));
    const wethNorm = Decimal(wethDenorm).div(Decimal(sumWeights));
    const daiNorm = Decimal(daiDenorm).div(Decimal(sumWeights));

    async function logAndAssertCurrentBalances() {
        let expected = currentPoolBalance;
        let actual = await pool.totalSupply();
        actual = Decimal(fromWei(actual));
        let relDif = calcRelativeDiff(expected, actual);
        if (verbose) {
            console.log('Pool Balance');
            console.log(`expected: ${expected}`);
            console.log(`actual  : ${actual}`);
            console.log(`relDif  : ${relDif}`);
        }

        assert.isAtMost(relDif.toNumber(), errorDelta);

        expected = currentWethBalance;
        actual = await pool.getBalance(WETH);
        actual = Decimal(fromWei(actual));
        relDif = calcRelativeDiff(expected, actual);
        if (verbose) {
            console.log('WETH Balance');
            console.log(`expected: ${expected}`);
            console.log(`actual  : ${actual}`);
            console.log(`relDif  : ${relDif}`);
        }

        assert.isAtMost(relDif.toNumber(), errorDelta);

        expected = currentDaiBalance;
        actual = await pool.getBalance(DAI);
        actual = Decimal(fromWei(actual));
        relDif = calcRelativeDiff(expected, actual);
        if (verbose) {
            console.log('Dai Balance');
            console.log(`expected: ${expected}`);
            console.log(`actual  : ${actual}`);
            console.log(`relDif  : ${relDif}`);
        }

        assert.isAtMost(relDif.toNumber(), errorDelta);
    }

    before(async () => {
        factory = await Factory.deployed();

        POOL = await factory.newPool.call(); // this works fine in clean room
        await factory.newPool();
        pool = await Pool.at(POOL);

        weth = await TToken.new('Wrapped Ether', 'WETH', 18);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18);

        WETH = weth.address;
        DAI = dai.address;

        await weth.mint(admin, MAX);
        await dai.mint(admin, MAX);

        await weth.approve(POOL, MAX);
        await dai.approve(POOL, MAX);

		wethOracle = await TConstantOracle.new(toWei("1000"), now);
        daiOracle = await TConstantOracle.new(toWei("49000"), now);

        await pool.bindMMM(WETH, toWei(wethBalance), toWei(wethDenorm), wethOracle.address);
        await pool.bindMMM(DAI, toWei(daiBalance), toWei(daiDenorm), daiOracle.address);

        await pool.setPublicSwap(true);

        await pool.setSwapFee(toWei(String(swapFee)));
    });

    describe('Extreme weights', () => {
        it('swapExactAmountIn', async () => {
            const tokenIn = WETH;
            const tokenInAmount = toWei('0.005');
            const tokenOut = DAI;
            const minAmountOut = toWei('0');
            const maxPrice = MAX;

            const output = await pool.swapExactAmountInMMM.call(
                tokenIn, tokenInAmount, tokenOut, minAmountOut, maxPrice,
            );

            // Checking outputs
            let expected = Decimal('0.00010193851551321131');
            let actual = Decimal(fromWei(output.tokenAmountOut));
            let relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[0]');
                console.log(`expected: ${expected}`);
                console.log(`actual  : ${actual}`);
                console.log(`relDif  : ${relDif}`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            expected = Decimal('49.04929929430706');
            actual = Decimal(fromWei(output.spotPriceAfter));
            relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[1]');
                console.log(`expected: ${expected}`);
                console.log(`actual  : ${actual}`);
                console.log(`relDif  : ${relDif}`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

        });

        it('swapExactAmountOutMMM', async () => {
            const tokenIn = WETH;
            const maxAmountIn = MAX;
            const tokenOut = DAI;
            const tokenAmountOut = toWei('0.33333333333333');
            const maxPrice = MAX;

            const output = await pool.swapExactAmountOutMMM.call(
                tokenIn, maxAmountIn, tokenOut, tokenAmountOut, maxPrice,
            );

            // Checking outputs
            let expected = Decimal('16.486705800677345');
            let actual = Decimal(fromWei(output.tokenAmountIn));
            let relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[0]');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            expected = Decimal('49.87433106754624');
            actual = Decimal(fromWei(output.spotPriceAfter));
            relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[1]');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('joinPool', async () => {
            currentPoolBalance = '100';
            await pool.finalize();

            // // Call function
            const poolAmountOut = '1';
            await pool.joinPool(toWei(poolAmountOut), [MAX, MAX]);

            // // Update balance states
            previousPoolBalance = Decimal(currentPoolBalance);
            currentPoolBalance = Decimal(currentPoolBalance).add(Decimal(poolAmountOut));

            // Balances of all tokens increase proportionally to the pool balance
            previousWethBalance = currentWethBalance;
            let balanceChange = (Decimal(poolAmountOut).div(previousPoolBalance)).mul(previousWethBalance);
            currentWethBalance = currentWethBalance.add(balanceChange);
            previousDaiBalance = currentDaiBalance;
            balanceChange = (Decimal(poolAmountOut).div(previousPoolBalance)).mul(previousDaiBalance);
            currentDaiBalance = currentDaiBalance.add(balanceChange);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });

        it('exitPool', async () => {
            // Call function
            // so that the balances of all tokens will go back exactly to what they were before joinPool()
            const poolAmountIn = 1 / (1 - exitFee);
            const poolAmountInAfterExitFee = Decimal(poolAmountIn).mul(Decimal(1).sub(exitFee));

            await pool.exitPool(toWei(String(poolAmountIn)), [toWei('0'), toWei('0')]);

            // Update balance states
            previousPoolBalance = currentPoolBalance;
            currentPoolBalance = currentPoolBalance.sub(poolAmountInAfterExitFee);
            // Balances of all tokens increase proportionally to the pool balance
            previousWethBalance = currentWethBalance;
            let balanceChange = (poolAmountInAfterExitFee.div(previousPoolBalance)).mul(previousWethBalance);
            currentWethBalance = currentWethBalance.sub(balanceChange);
            previousDaiBalance = currentDaiBalance;
            balanceChange = (poolAmountInAfterExitFee.div(previousPoolBalance)).mul(previousDaiBalance);
            currentDaiBalance = currentDaiBalance.sub(balanceChange);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });

        it('joinswapExternAmountInMMM', async () => {
            // Call function
            const tokenRatio = 1.01;
            // increase tbalance by 1.1 after swap fee
            const tokenAmountIn = (1 / (1 - swapFee * (1 - wethNorm))) * (currentWethBalance * (tokenRatio - 1));
            await pool.joinswapExternAmountInMMM(WETH, toWei(String(tokenAmountIn)), toWei('0'));
            // Update balance states
            previousWethBalance = currentWethBalance;
            currentWethBalance = currentWethBalance.add(Decimal(tokenAmountIn));
            previousPoolBalance = currentPoolBalance;
            currentPoolBalance = currentPoolBalance.mul(Decimal(tokenRatio).pow(wethNorm)); // increase by 1.1**wethNorm

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });


        it('joinswapPoolAmountOutMMM', async () => {
            // Call function
            const poolRatio = 1.01;
            const poolAmountOut = currentPoolBalance * (poolRatio - 1);
            await pool.joinswapPoolAmountOutMMM(DAI, toWei(String(poolAmountOut)), MAX);
            // Update balance states
            previousPoolBalance = currentPoolBalance;
            currentPoolBalance = currentPoolBalance.mul(Decimal(poolRatio)); // increase by 1.1
            previousDaiBalance = currentDaiBalance;
            const numer = previousDaiBalance.mul(Decimal(poolRatio).pow(Decimal(1).div(daiNorm)).sub(Decimal(1)));
            const denom = Decimal(1).sub((Decimal(swapFee)).mul((Decimal(1).sub(daiNorm))));
            currentDaiBalance = currentDaiBalance.plus(numer.div(denom));

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });

        it('joinswapExternAmountInMMM should revert', async () => {
            // Call function
            const tokenRatio = 1.1;
            const tokenAmountIn = (1 / (1 - swapFee * (1 - wethNorm))) * (currentWethBalance * (tokenRatio));
            
            try {
                await pool.joinswapExternAmountInMMM(WETH, toWei(String(tokenAmountIn)), toWei('0'))
            }
            catch(e) {
                assert.equal(e.reason, '40');
            }
            /*
            await truffleAssert.reverts(
                pool.joinswapExternAmountInMMM(WETH, toWei(String(tokenAmountIn)), toWei('0')),
                '40',
            );
            */
        });

        it('joinswapPoolAmountOutMMM should revert', async () => {
            // Call function
            const poolRatio = 0.9;
            const poolAmountOut = currentPoolBalance * (poolRatio);
            
            try {
                await pool.joinswapPoolAmountOutMMM(DAI, toWei(String(poolAmountOut)), MAX)
            }
            catch(e) {
                assert.equal(e.reason, '44');
            }
            /*
            await truffleAssert.reverts(
                pool.joinswapPoolAmountOutMMM(DAI, toWei(String(poolAmountOut)), MAX),
                '44',
            );*/
        });

        /* tokenRatioBeforeSwapFee > 1 ==> tokenAmountOut is negative
        it('exitswapExternAmountOutMMM should revert', async () => {
            // Call function
            const poolRatioAfterExitFee = 1.1;
            const tokenRatioBeforeSwapFee = poolRatioAfterExitFee ** (1 / daiNorm);
            const tokenAmountOut = currentDaiBalance * (1 - tokenRatioBeforeSwapFee) * (1 - swapFee * (1 - daiNorm));
            await truffleAssert.reverts(
                pool.exitswapExternAmountOutMMM(DAI, toWei(String(tokenAmountOut)), MAX),
                '7',
            );
            
        });
        */

        it('exitswapPoolAmountInMMM should revert', async () => {
            // Call function
            const poolRatioAfterExitFee = 0.9;
            const poolAmountIn = currentPoolBalance * (1 - poolRatioAfterExitFee) * (1 / (1 - exitFee));
            
            try {

                await pool.exitswapPoolAmountInMMM(WETH, toWei(String(poolAmountIn)), toWei('0'))
            }
            catch(e) {
                assert.equal(e.reason, '44');
            }
            /*
            await truffleAssert.reverts(
                pool.exitswapPoolAmountInMMM(WETH, toWei(String(poolAmountIn)), toWei('0')),
                '44',
            );
            */
        });

        it('exitswapExternAmountOutMMM', async () => {
            // Call functionc
            const poolRatioAfterExitFee = 0.99;
            const tokenRatioBeforeSwapFee = poolRatioAfterExitFee ** (1 / daiNorm);
            const tokenAmountOut = currentDaiBalance * (1 - tokenRatioBeforeSwapFee) * (1 - swapFee * (1 - daiNorm));
            await pool.exitswapExternAmountOutMMM(DAI, toWei(String(tokenAmountOut)), MAX);
            // Update balance states
            previousDaiBalance = currentDaiBalance;
            currentDaiBalance = currentDaiBalance.sub(Decimal(tokenAmountOut));
            previousPoolBalance = currentPoolBalance;
            const balanceChange = previousPoolBalance.mul(Decimal(1).sub(Decimal(poolRatioAfterExitFee)));
            currentPoolBalance = currentPoolBalance.sub(balanceChange);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });
        
        it('poolAmountOut = joinswapExternAmountInMMM(joinswapPoolAmountOutMMM(poolAmountOut))', async () => {
            const poolAmountOut = 0.1;
            const tokenAmountIn = await pool.joinswapPoolAmountOutMMM.call(DAI, toWei(String(poolAmountOut)), MAX);
            const pAo = await pool.joinswapExternAmountInMMM.call(DAI, String(tokenAmountIn), toWei('0'));

            const expected = Decimal(poolAmountOut);
            const actual = Decimal(fromWei(pAo));
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log(`tokenAmountIn: ${tokenAmountIn})`);
                console.log('poolAmountOut');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('tokenAmountIn = joinswapPoolAmountOutMMM(joinswapExternAmountInMMM(tokenAmountIn))', async () => {
            const tokenAmountIn = '1';
            const poolAmountOut = await pool.joinswapExternAmountInMMM.call(DAI, toWei(tokenAmountIn), toWei('0'));
            const calculatedtokenAmountIn = await pool.joinswapPoolAmountOutMMM.call(DAI, String(poolAmountOut), MAX);

            const expected = Decimal(tokenAmountIn);
            const actual = Decimal(fromWei(calculatedtokenAmountIn));
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log(`poolAmountOut: ${poolAmountOut})`);
                console.log('tokenAmountIn');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('poolAmountIn = exitswapExternAmountOutMMM(exitswapPoolAmountInMMM(poolAmountIn))', async () => {
            const poolAmountIn = 0.01;
            const tokenAmountOut = await pool.exitswapPoolAmountInMMM.call(WETH, toWei(String(poolAmountIn)), toWei('0'));
            const calculatedpoolAmountIn = await pool.exitswapExternAmountOutMMM.call(WETH, String(tokenAmountOut), MAX);

            const expected = Decimal(poolAmountIn);
            const actual = Decimal(fromWei(calculatedpoolAmountIn));
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log(`tokenAmountOut: ${tokenAmountOut})`);
                console.log('poolAmountIn');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('tokenAmountOut = exitswapPoolAmountInMMM(exitswapExternAmountOutMMM(tokenAmountOut))', async () => {
            const tokenAmountOut = 1;
            const poolAmountIn = await pool.exitswapExternAmountOutMMM.call(DAI, toWei(String(tokenAmountOut)), MAX);
            const tAo = await pool.exitswapPoolAmountInMMM.call(DAI, String(poolAmountIn), toWei('0'));

            const expected = Decimal(tokenAmountOut);
            const actual = Decimal(fromWei(tAo));
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log(`poolAmountIn: ${poolAmountIn})`);
                console.log('tokenAmountOut');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });
    });
});
