const Decimal = require('decimal.js');
const {
    calcSpotPrice,
    calcOutGivenIn,
    calcInGivenOut,
    calcRelativeDiff,
} = require('../lib/calc_comparisons');
const {
    advanceBlock
} = require('../lib/time');

const Pool = artifacts.require('Pool');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');
const errorDelta = 10 ** -8;
const swapFee = 10 ** -3; // 0.001;
const exitFee = 0;
const verbose = process.env.VERBOSE;
const TConstantOracle = artifacts.require('TConstantOracle');

contract('Pool', async (accounts) => {

	const now = 1641893000;

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const admin = accounts[0];

    const MAX = web3.utils.toTwosComplement(-1);

    let WETH; let DAI; // addresses
    let weth; let dai; // TTokens
    let factory; // Pool factory
    let pool; // first pool w/ defaults
    let POOL; //   pool address

    let wethOracle;
    let daiOracle;

    const wethBalance = '4';
    const wethDenorm = '10';

    let currentWethBalance = Decimal(wethBalance);
    let previousWethBalance = currentWethBalance;

    const daiBalance = '12000';
    const daiDenorm = '10';

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

        // 1 weth = 3000 dai
		wethOracle = await TConstantOracle.new(300000000000, now);
		daiOracle = await TConstantOracle.new(100000000, now);

        await pool.bindMMM(WETH, toWei(wethBalance), toWei(wethDenorm), wethOracle.address);
        await pool.bindMMM(DAI, toWei(daiBalance), toWei(daiDenorm), daiOracle.address);

        await pool.setPublicSwap(true);
        await pool.setSwapFee(toWei(String(swapFee)));
    });

    describe('With fees', () => {
        it('swapExactAmountIn', async () => {
            const tokenIn = WETH;
            const tokenAmountIn = '0.02';
            const tokenOut = DAI;
            const minAmountOut = '0';
            const maxPrice = MAX;

            const output = await pool.swapExactAmountInMMM.call(
                tokenIn,
                toWei(tokenAmountIn),
                tokenOut,
                toWei(minAmountOut),
                maxPrice,
            );

            // Checking outputs
            let expected = calcOutGivenIn(
                currentWethBalance,
                wethNorm,
                currentDaiBalance,
                daiNorm,
                tokenAmountIn,
                swapFee,
            );

            let actual = Decimal(fromWei(output[0]));
            let relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[0]');
                console.log(`expected: ${expected}`);
                console.log(`actual  : ${actual}`);
                console.log(`relDif  : ${relDif}`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            expected = calcSpotPrice(
                currentWethBalance.plus(Decimal(tokenAmountIn)),
                wethNorm,
                currentDaiBalance.sub(actual),
                daiNorm,
                swapFee,
            );
            // expected = 1 / ((1 - swapFee) * (4 + 2)) / (48 / (4 + 2 * (1 - swapFee)));
            // expected = ((1 / (1 - swapFee)) * (4 + 2)) / (48 / (4 + 2 * (1 - swapFee)));
            actual = fromWei(output[1]);
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
            const tokenIn = DAI;
            const maxAmountIn = MAX;
            const tokenOut = WETH;
            const tokenAmountOut = '0.02';
            const maxPrice = MAX;

            const output = await pool.swapExactAmountOutMMM.call(
                tokenIn,
                maxAmountIn,
                tokenOut,
                toWei(tokenAmountOut),
                maxPrice,
            );

            // Checking outputs
            // let expected = (48 / (4 - 1) - 12) / (1 - swapFee);
            let expected = calcInGivenOut(
                currentDaiBalance,
                daiNorm,
                currentWethBalance,
                wethNorm,
                tokenAmountOut,
                swapFee,
            );

            let actual = fromWei(output[0]);
            let relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[0]');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            expected = calcSpotPrice(
                currentDaiBalance.plus(actual),
                daiNorm,
                currentWethBalance.sub(Decimal(tokenAmountOut)),
                wethNorm,
                swapFee,
            );

            actual = fromWei(output[1]);
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

            // Call function
            const pAo = '1';
            await pool.joinPool(toWei(pAo), [MAX, MAX]);

            // Update balance states
            previousPoolBalance = Decimal(currentPoolBalance);
            currentPoolBalance = Decimal(currentPoolBalance).plus(Decimal(pAo));
            // Balances of all tokens increase proportionally to the pool balance
            previousWethBalance = currentWethBalance;
            let balanceChange = (Decimal(pAo).div(previousPoolBalance)).mul(previousWethBalance);
            currentWethBalance = currentWethBalance.plus(balanceChange);
            previousDaiBalance = currentDaiBalance;
            balanceChange = (Decimal(pAo).div(previousPoolBalance)).mul(previousDaiBalance);
            currentDaiBalance = currentDaiBalance.plus(balanceChange);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });

        it('exitPool', async () => {
            // Call function
            // so that the balances of all tokens will go back exactly to what they were before joinPool()
            const pAi = 1 / (1 - exitFee);
            const pAiAfterExitFee = pAi * (1 - exitFee);

            // Necessary for JIT protection block waiting time
            await advanceBlock(3);
            await pool.exitPool(toWei(String(pAi)), [toWei('0'), toWei('0')]);

            // Update balance states
            previousPoolBalance = currentPoolBalance;
            currentPoolBalance = currentPoolBalance.sub(Decimal(pAiAfterExitFee));
            // Balances of all tokens increase proportionally to the pool balance
            previousWethBalance = currentWethBalance;
            let balanceChange = (Decimal(pAiAfterExitFee).div(previousPoolBalance)).mul(previousWethBalance);
            currentWethBalance = currentWethBalance.sub(balanceChange);
            previousDaiBalance = currentDaiBalance;
            balanceChange = (Decimal(pAiAfterExitFee).div(previousPoolBalance)).mul(previousDaiBalance);
            currentDaiBalance = currentDaiBalance.sub(balanceChange);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });

        it('joinswapExternAmountInMMM', async () => {
            // Call function
            const poolRatio = 1.005;
            // increase tbalance by 1.005^2 after swap fee
            const tAi = (1 / (1 - swapFee * (1 - wethNorm))) * (currentWethBalance * (poolRatio ** (1 / wethNorm) - 1));

            const pAo = await pool.joinswapExternAmountInMMM.call(WETH, toWei(String(tAi)), toWei('0'));
            // Execute txn called above
            await pool.joinswapExternAmountInMMM(WETH, toWei(String(tAi)), toWei('0'));

            // Update balance states
            previousWethBalance = currentWethBalance;
            currentWethBalance = currentWethBalance.plus(Decimal(tAi));
            previousPoolBalance = currentPoolBalance;
            currentPoolBalance = currentPoolBalance.mul(Decimal(poolRatio)); // increase by 1.1

            // Check pAo
            const expected = (currentPoolBalance.sub(previousPoolBalance)); // poolRatio = 1.1
            const actual = fromWei(pAo);
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('pAo');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }
            assert.isAtMost(relDif.toNumber(), errorDelta);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });

        it('joinswapPoolAmountOutMMM', async () => {
            // Call function
            const poolRatio = 1.005;
            const pAo = currentPoolBalance * (poolRatio - 1);

            const tAi = await pool.joinswapPoolAmountOutMMM.call(DAI, toWei(String(pAo)), MAX); // 10% of current supply
            await pool.joinswapPoolAmountOutMMM(DAI, toWei(String(pAo)), MAX);

            // Update balance states
            previousPoolBalance = currentPoolBalance;
            currentPoolBalance = currentPoolBalance.mul(Decimal(poolRatio)); // increase by 1.1
            previousDaiBalance = currentDaiBalance;
            // (21% + swap fees) addition to current Rock supply ;
            const numer = (previousDaiBalance * ((poolRatio ** (1 / daiNorm) - 1) * 1));
            const denom = (1 - swapFee * (1 - daiNorm));
            currentDaiBalance = currentDaiBalance.plus(Decimal(numer / denom));

            // Check tAi
            const expected = (currentDaiBalance.sub(previousDaiBalance)); // 0.4641 -> 1.1^4 - 1 = 0.4641
            const actual = fromWei(tAi);
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('tAi');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }
            assert.isAtMost(relDif.toNumber(), errorDelta);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });

        it('exitswapPoolAmountIn', async () => {
            // Call function
            const poolRatioAfterExitFee = 0.995;
            const pAi = currentPoolBalance * (1 - poolRatioAfterExitFee) * (1 / (1 - exitFee));
  
            await advanceBlock(3);
            // newPool() Transaction is sent to mine blocks so we can call next line with no errors
            await factory.newPool();

            const tAo = await pool.exitswapPoolAmountInMMM.call(WETH, toWei(String(pAi)), toWei('0'));

            // Necessary for JIT protection block waiting time
            await advanceBlock(3);
            await pool.exitswapPoolAmountInMMM(WETH, toWei(String(pAi)), toWei('0'));

            // Update balance states
            previousPoolBalance = currentPoolBalance;
            currentPoolBalance = currentPoolBalance.sub(Decimal(pAi).mul(Decimal(1).sub(Decimal(exitFee))));
            previousWethBalance = currentWethBalance;
            const mult = (1 - poolRatioAfterExitFee ** (1 / wethNorm)) * (1 - swapFee * (1 - wethNorm));
            currentWethBalance = currentWethBalance.sub(previousWethBalance.mul(Decimal(mult)));

            // Check tAo
            const expected = (previousWethBalance.sub(currentWethBalance)); // 0.4641 -> 1.1^4 - 1 = 0.4641
            const actual = fromWei(tAo);
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('tAo');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });

        it('exitswapExternAmountOut', async () => {
            // Call function
            const poolRatioAfterExitFee = 0.995;
            const tokenRatioBeforeSwapFee = poolRatioAfterExitFee ** (1 / daiNorm);
            const tAo = currentDaiBalance * (1 - tokenRatioBeforeSwapFee) * (1 - swapFee * (1 - daiNorm));
            await advanceBlock(3);
            const pAi = await pool.exitswapExternAmountOutMMM.call(DAI, toWei(String(tAo)), MAX);
            await pool.exitswapExternAmountOutMMM(DAI, toWei(String(tAo)), MAX);

            // Update balance states
            previousDaiBalance = currentDaiBalance;
            currentDaiBalance = currentDaiBalance.sub(Decimal(tAo));
            previousPoolBalance = currentPoolBalance;
            const balanceChange = previousPoolBalance.mul(Decimal(1).sub(Decimal(poolRatioAfterExitFee)));
            currentPoolBalance = currentPoolBalance.sub(balanceChange);

            // check pAi
            // Notice the (1-exitFee) term since only pAi*(1-exitFee) is burned
            const expected = (previousPoolBalance.sub(currentPoolBalance)).div(Decimal(1).sub(Decimal(exitFee)));
            const actual = fromWei(pAi);
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('pAi');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });

        it('pAo = joinswapExternAmountInMMM(joinswapPoolAmountOutMMM(pAo))', async () => {
            const pAo = 0.5;
            const tAi = await pool.joinswapPoolAmountOutMMM.call(WETH, toWei(String(pAo)), MAX);
            const calculatedPAo = await pool.joinswapExternAmountInMMM.call(WETH, String(tAi), toWei('0'));

            const expected = Decimal(pAo);
            const actual = fromWei(calculatedPAo);
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log(`tAi: ${tAi})`);
                console.log('pAo');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('tAi = joinswapPoolAmountOutMMM(joinswapExternAmountInMMM(tAi))', async () => {
            const tAi = 1;
            const pAo = await pool.joinswapExternAmountInMMM.call(DAI, toWei(String(tAi)), toWei('0'));
            const calculatedtAi = await pool.joinswapPoolAmountOutMMM.call(DAI, String(pAo), MAX);

            const expected = Decimal(tAi);
            const actual = fromWei(calculatedtAi);
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log(`pAo: ${pAo})`);
                console.log('tAi');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('pAi = exitswapExternAmountOutMMM(exitswapPoolAmountInMMM(pAi))', async () => {
            const pAi = 0.01;

            // Necessary for JIT protection block waiting time
            await advanceBlock(3);
            const tAo = await pool.exitswapPoolAmountInMMM.call(WETH, toWei(String(pAi)), toWei('0'));
            const calculatedPAi = await pool.exitswapExternAmountOutMMM.call(WETH, String(tAo), MAX);

            const expected = Decimal(pAi);
            const actual = fromWei(calculatedPAi);
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log(`tAo: ${tAo})`);
                console.log('pAi');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('tAo = exitswapPoolAmountInMMM(exitswapExternAmountOutMMM(tAo))', async () => {
            const tAo = '1';
            const pAi = await pool.exitswapExternAmountOutMMM.call(DAI, toWei(tAo), MAX);
            const calculatedtAo = await pool.exitswapPoolAmountInMMM.call(DAI, String(pAi), toWei('0'));

            const expected = Decimal(tAo);
            const actual = fromWei(calculatedtAo);
            const relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log(`pAi: ${pAi})`);
                console.log('tAo');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });
    });
});
