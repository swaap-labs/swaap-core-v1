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

		wethOracle = await TConstantOracle.new(300000000000, now);
        daiOracle = await TConstantOracle.new(100000000, now);

        await pool.bindMMM(WETH, toWei(wethBalance), toWei(wethDenorm), wethOracle.address);
        await pool.bindMMM(DAI, toWei(daiBalance), toWei(daiDenorm), daiOracle.address);

        await pool.setPublicSwap(true);

        await pool.setSwapFee(toWei(String(swapFee)));
    });

    describe('Extreme weights', () => {
        it('swapExactAmountIn', async () => {
            const tokenIn = WETH;
            const tokenInAmount = toWei('500');
            const tokenOut = DAI;
            const minAmountOut = toWei('0');
            const maxPrice = MAX;

            const output = await pool.swapExactAmountInMMM.call(
                tokenIn, tokenInAmount, tokenOut, minAmountOut, maxPrice,
            );

            // Checking outputs
            let expected = Decimal('8.23390841016124456');
            let actual = Decimal(fromWei(output.tokenAmountOut));
            let relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[0]');
                console.log(`expected: ${expected}`);
                console.log(`actual  : ${actual}`);
                console.log(`relDif  : ${relDif}`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            expected = Decimal('74.1844011380065814');
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
            const tokenAmountOut = toWei('333.333333333333333333');
            const maxPrice = MAX;

            const output = await pool.swapExactAmountOutMMM.call(
                tokenIn, maxAmountIn, tokenOut, tokenAmountOut, maxPrice,
            );

            // Checking outputs
            let expected = Decimal('425506505648.348073');
            let actual = Decimal(fromWei(output.tokenAmountIn));
            let relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[0]');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            expected = Decimal('31306034272.9265099');
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
    });
});
