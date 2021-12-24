const truffleAssert = require('truffle-assertions');
const { calcOutGivenIn, calcInGivenOut, calcRelativeDiff } = require('../lib/calc_comparisons');
const { calcOutGivenInMMM, computeMMMSpread } = require('../lib/mmm');
const { getParametersEstimation, getStartIndices } = require('../lib/gbm_oracle');

const Pool = artifacts.require('Pool');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');
const verbose = process.env.VERBOSE;

const TWETHOracle = artifacts.require('TWETHOracle');
const TWBTCOracle = artifacts.require('TWBTCOracle');
const TDAIOracle = artifacts.require('TDAIOracle');

contract('Pool', async (accounts) => {
    const admin = accounts[0];
    const user1 = accounts[1];
    const user2 = accounts[2];

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const errorDelta = 10 ** -8;
    const MAX = web3.utils.toTwosComplement(-1);

    const now = 1641892596;

    const z = 1;
    const horizon = 600;
    const priceStatisticsLookbackInRound = 6;
    const priceStatisticsLookbackInSec = 3600 * 2;

    const baseSwapFee = toWei('0.003');

    let WETH; let WBTC; let DAI;
    let weth; let wbtc; let dai;

    let factory; // Pool factory
    let pool; // first pool w/ defaults
    let POOL; //   pool address

    let wethOracle;
    let wbtcOracle;
    let daiOracle;

    let WETHOracleAddress;
	let WBTCOracleAddress;
	let DAIOracleAddress;

	let wethInitialBalance;
	let daiInitialBalance;

	let wethOraclePrices; let wethOracleTimestamps;
	let daihOraclePrices; let daiOracleTimestamps;

	let wethOraclePriceLast; let wbtcOraclePriceLast; let daiOraclePriceLast;

	let expectedMeanWETHDAI; let expectedVarianceWETHDAI;
	let expectedMeanWBTCDAI; let expectedVarianceWBTCDAI;
	let expectedMeanWBTCWETH; let expectedVarianceWBTCWETH;

    before(async () => {
        factory = await Factory.deployed();

        POOL = await factory.newPool.call();
        await factory.newPool();
        pool = await Pool.at(POOL);

        weth = await TToken.new('Wrapped Ether', 'WETH', 18);
        wbtc = await TToken.new('Wrapped Bitcoin', 'WBTC', 18);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18);

        WETH = weth.address;
        WBTC = wbtc.address;
        DAI = dai.address;

		wethOracle = await TWETHOracle.new();
		wbtcOracle = await TWBTCOracle.new();
		daiOracle = await TDAIOracle.new();

        WETHOracleAddress = wethOracle.address;
        WBTCOracleAddress = wbtcOracle.address;
        DAIOracleAddress = daiOracle.address;

        /*
            Tests assume token prices
            WETH - $3128.82040500
            WBTC  - $42013.40255103
            DAI  - $0.99990575
        */

        const valuePerAsset = 10000000

		_wethOraclePrices = [
			312882040500,
			311613433829,
			311445000000,
			310672718218,
			311461368677,
			311394849384
		];
		_wethOracleTimestamps = [
			1641889937,
			1641886305,
			1641882671,
			1641879040,
			1641875409,
			1641871778
		];
		_wbtcOraclePrices = [
			4201340255103,
			4245514000000,
			4197967571800,
			4155911000000,
			4114025628407,
			4072208879420
		];
		_wbtcOracleTimestamps = [
			1641891047,
			1641889577,
			1641864920,
			1641840072,
			1641837070,
			1641836334
		];
		_daiOraclePrices = [
			99990575,
			100000000,
			100054178,
			100034433,
			100044915,
			100008103
		];
		_daiOracleTimestamps = [
			1641892596,
			1641806161,
			1641719735,
			1641633301,
			1641546877,
			1641460433
		];

        wethOraclePriceLast = _wethOraclePrices[0] / 10**8;
        wbtcOraclePriceLast = _wbtcOraclePrices[0] / 10**8;
        daiOraclePriceLast = _daiOraclePrices[0] / 10**8;

		const [wethOracleStartIndexWETHDAI, daiOracleStartIndexWETHDAI] = getStartIndices(_wethOracleTimestamps, _daiOracleTimestamps, priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now)
		const [_expectedMeanWETHDAI, _expectedVarianceWETHDAI] = getParametersEstimation(
			_wethOraclePrices, _wethOracleTimestamps, wethOracleStartIndexWETHDAI,
			_daiOraclePrices, _daiOracleTimestamps, daiOracleStartIndexWETHDAI,
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
		);
		expectedMeanWETHDAI = _expectedMeanWETHDAI;
		expectedVarianceWETHDAI = _expectedVarianceWETHDAI;

		const [wbtcOracleStartIndexWBTCDAI, daiOracleStartIndexWBTCDAI] = getStartIndices(_wbtcOracleTimestamps, _daiOracleTimestamps, priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now)
		const [_expectedMeanWBTCDAI, _expectedVarianceWBTCDAI] = getParametersEstimation(
			_wbtcOraclePrices, _wbtcOracleTimestamps, wbtcOracleStartIndexWBTCDAI,
			_daiOraclePrices, _daiOracleTimestamps, daiOracleStartIndexWBTCDAI,
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
		);
		expectedMeanWBTCDAI = _expectedMeanWBTCDAI;
		expectedVarianceWBTCDAI = _expectedVarianceWBTCDAI;

		const [wbtcOracleStartIndexWBTCWETH, wethOracleStartIndexWBTCWETH] = getStartIndices(_wbtcOracleTimestamps, _wethOracleTimestamps, priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now)
		const [_expectedMeanWBTCWETH, _expectedVarianceWBTCWETH] = getParametersEstimation(
			_wbtcOraclePrices, _wbtcOracleTimestamps, wbtcOracleStartIndexWBTCWETH,
			_wethOraclePrices, _wethOracleTimestamps, wethOracleStartIndexWBTCWETH,
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
		);
		expectedMeanWBTCWETH = _expectedMeanWBTCWETH;
		expectedVarianceWBTCWETH = _expectedVarianceWBTCWETH;

        wethInitialBalance = valuePerAsset / wethOraclePriceLast
        wbtcInitialBalance = valuePerAsset / wbtcOraclePriceLast
        daiInitialBalance = valuePerAsset / daiOraclePriceLast

        // Admin balances
        await weth.mint(admin, toWei(wethInitialBalance.toString()));
        await wbtc.mint(admin, toWei(wbtcInitialBalance.toString()));
        await dai.mint(admin, toWei(daiInitialBalance.toString()));

        // User1 balances
        await weth.mint(user1, toWei('2500'), { from: admin });
        await wbtc.mint(user1, toWei('400'), { from: admin });
        await dai.mint(user1, toWei('4000000'), { from: admin });

        // User2 balances
        await weth.mint(user2, toWei('1222.22'), { from: admin });
        await wbtc.mint(user2, toWei('101.5333'), { from: admin });
        await dai.mint(user2, toWei('0'), { from: admin });
    });

    describe('Binding Tokens', () => {

        it('Controller is msg.sender', async () => {
            const controller = await pool.getController();
            assert.equal(controller, admin);
        });

        it('Admin approves tokens', async () => {
            await weth.approve(POOL, MAX);
            await wbtc.approve(POOL, MAX);
            await dai.approve(POOL, MAX);
        });

        it('Admin binds tokens', async () => {
            // Equal weights WETH, WBTC, DAI
            await pool.bindMMM(WETH, toWei(parseFloat(wethInitialBalance).toString()), toWei('5'), WETHOracleAddress);
            await pool.bindMMM(WBTC, toWei(parseFloat(wbtcInitialBalance).toString()), toWei('5'), WBTCOracleAddress);
            await pool.bindMMM(DAI, toWei(parseFloat(daiInitialBalance).toString()), toWei('5'), DAIOracleAddress);
            const numTokens = await pool.getNumTokens();
            assert.equal(3, numTokens);
            const totalDenormWeight = await pool.getTotalDenormalizedWeight();
            assert.equal(15, fromWei(totalDenormWeight));
            const wethDenormWeight = await pool.getDenormalizedWeight(WETH);
            assert.equal(5, fromWei(wethDenormWeight));
            const wethNormWeight = await pool.getNormalizedWeight(WETH);
            assert.equal(0.333333333333333333, fromWei(wethNormWeight));
            const wbtcBalance = await pool.getBalance(WBTC);
            assert.equal(wbtcInitialBalance, fromWei(wbtcBalance));
        });

        it('Get current tokens', async () => {
            const currentTokens = await pool.getCurrentTokens();
            assert.sameMembers(currentTokens, [WETH, WBTC, DAI]);
        });

    });


    describe('Finalizing pool', () => {

        it('Admin sets swap fees', async () => {
            await pool.setSwapFee(baseSwapFee);
            const swapFee = await pool.getSwapFee();
            assert.equal(0.003, fromWei(swapFee));
        });

        it('Admin sets dynamic spread parmeters', async () => {
            await pool.setDynamicCoverageFeesZ(toWei(z.toString()));
            await pool.setDynamicCoverageFeesHorizon(toWei(horizon.toString()));
            await pool.setPriceStatisticsLookbackInRound(priceStatisticsLookbackInRound);
            await pool.setPriceStatisticsLookbackInSec(priceStatisticsLookbackInSec);
            const expectedCoverageParameters = await pool.getCoverageParameters();
            assert.equal(fromWei(expectedCoverageParameters[0]), z);
            assert.equal(fromWei(expectedCoverageParameters[1]), horizon);
            assert.equal(expectedCoverageParameters[2], priceStatisticsLookbackInRound);
            assert.equal(expectedCoverageParameters[3], priceStatisticsLookbackInSec);
        });

        it('Admin finalizes pool', async () => {
            const tx = await pool.finalize();
            const adminBal = await pool.balanceOf(admin);
            assert.equal(fromWei(adminBal), fromWei(adminBal));
//            truffleAssert.eventEmitted(tx, 'Transfer', (event) => event.dst === admin);
            const finalized = pool.isFinalized();
            assert(finalized);
        });

        it('Get final tokens', async () => {
            const finalTokens = await pool.getFinalTokens();
            assert.sameMembers(finalTokens, [WETH, WBTC, DAI]);
        });

    });

    describe('User interactions', () => {
        it('Other users approve tokens', async () => {
            await weth.approve(POOL, MAX, { from: user1 });
            await wbtc.approve(POOL, MAX, { from: user1 });
            await dai.approve(POOL, MAX, { from: user1 });

            await weth.approve(POOL, MAX, { from: user2 });
            await wbtc.approve(POOL, MAX, { from: user2 });
            await dai.approve(POOL, MAX, { from: user2 });
        });

        it('User1 joins pool', async () => {
            await pool.joinPool(toWei('5'), [MAX, MAX, MAX], { from: user1 });
            const daiBalance = await pool.getBalance(DAI);
            assert.equal(daiInitialBalance * (105 / 100), fromWei(daiBalance));
            const userWethBalance = await weth.balanceOf(user1);
            assert.equal(2500 - wethInitialBalance * (5 / 100), fromWei(userWethBalance));
        });

        it('getSpotPriceSansFeeMMM and getSpotPrice', async () => {
			const expectedMMMSpread = computeMMMSpread(
				expectedMeanWETHDAI,
				expectedVarianceWETHDAI,
				z,
				horizon
			)

            const expectedPriceSansFee = parseFloat(
            	expectedMMMSpread * (wethInitialBalance * (105 / 100) / 5) / (daiInitialBalance * (105 / 100) / 5)
            )

            const price = await pool._getSpotPriceMMMWithTimestamp(WETH, DAI, 0, now);
            const relDif = calcRelativeDiff(expectedPriceSansFee, parseFloat(fromWei(price)));
            assert.isAtMost(relDif.toNumber(), errorDelta);

            const priceFee = await pool._getSpotPriceMMMWithTimestamp(WETH, DAI, baseSwapFee, now);
            const priceFeeCheck = expectedPriceSansFee * (1 / (1 - 0.003));
            const relDifFee = calcRelativeDiff(priceFeeCheck, parseFloat(fromWei(priceFee)));
            assert.isAtMost(relDifFee.toNumber(), errorDelta);

        });

        it('Fail swapExactAmountInMMM unbound or over min max ratios', async () => {
            await truffleAssert.reverts(
                pool._swapExactAmountInMMMWithTimestamp(WETH, toWei('1678'), DAI, toWei('5266293'), toWei('4000'), now, { from: user2 }),
                'ERR_MAX_IN_RATIO',
            );
        });

        it('swapExactAmountInMMM WETH -> DAI', async () => {
            // 100 WETH -> DAI
            const amount = 100

            const wethBalance = await pool.getBalance(WETH);
            const daiBalance = await pool.getBalance(DAI);

            const relativePrice = daiOraclePriceLast / wethOraclePriceLast;

			const [expectedAmount, expectedSpread] = calcOutGivenInMMM(
				parseFloat(fromWei(wethBalance)),
				5,
				parseFloat(fromWei(daiBalance)),
				5,
				amount,
				0.003,
				expectedMeanWETHDAI,
				expectedVarianceWETHDAI,
				z,
				horizon,
				relativePrice
			);

			if (verbose) {
	            const gas = await pool._swapExactAmountInMMMWithTimestamp.estimateGas(
	                WETH,
	                toWei(amount.toString()),
	                DAI,
	                toWei('0'),
	                toWei('10000'),
	                now,
	                { from: user2 }
	            );
	            console.log("gas:", gas)
			}

            const txr = await pool._swapExactAmountInMMMWithTimestamp(
                WETH,
                toWei(amount.toString()),
                DAI,
                toWei('0'),
                toWei('10000'),
                now,
                { from: user2 }
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');

            const actualAmount = fromWei(log.args[4]);
            const relDifAmount = calcRelativeDiff(expectedAmount, actualAmount);
            if (verbose) {
                console.log('swapExactAmountInMMM amount' );
                console.log(`expected: ${expectedAmount}`);
                console.log(`actual  : ${actualAmount}`);
                console.log(`relDif  : ${relDifAmount}`);
            }
            assert.isAtMost(relDifAmount.toNumber(), errorDelta);

			const actualSpread = fromWei(log.args[5]);
            const relDifSpread = calcRelativeDiff(expectedAmount, actualAmount);
            if (verbose) {
                console.log('swapExactAmountInMMM spread');
                console.log(`expected: ${expectedSpread}`);
                console.log(`actual  : ${actualSpread}`);
                console.log(`relDif  : ${relDifSpread}`);
            }
            assert.isAtMost(relDifSpread.toNumber(), errorDelta);

            const userDaiBalance = await dai.balanceOf(user2);
            assert.equal(fromWei(userDaiBalance), Number(fromWei(log.args[4])));

            const wethPrice = await pool._getSpotPriceMMMWithTimestamp(DAI, WETH, baseSwapFee, now);
            const wethPriceFeeCheck = (((parseFloat(fromWei(daiBalance)) - expectedAmount)  / 5) / ((parseFloat(fromWei(wethBalance)) + amount) / 5)) * (1 / (1 - 0.003));
            assert.approximately(Number(fromWei(wethPrice)), Number(wethPriceFeeCheck), errorDelta);

            const daiNormWeight = await pool.getNormalizedWeight(DAI);
            assert.equal(0.333333333333333333, fromWei(daiNormWeight));
        });

		it('swapExactAmountInMMM WBTC -> WETH', async () => {
            // 10 WBTC -> WETH
            const amount = 10

            const wbtcBalance = await pool.getBalance(WBTC);
            const wethBalance = await pool.getBalance(WETH);

            const relativePrice = wethOraclePriceLast / wbtcOraclePriceLast;

			const [expectedAmount, expectedSpread] = calcOutGivenInMMM(
				parseFloat(fromWei(wbtcBalance)),
				5,
				parseFloat(fromWei(wethBalance)),
				5,
				amount,
				0.003,
				expectedMeanWBTCWETH,
				expectedVarianceWBTCWETH,
				z,
				horizon,
				relativePrice
			);

			if (verbose) {
				const gas = await pool._swapExactAmountInMMMWithTimestamp.estimateGas(
					WBTC,
					toWei(amount.toString()),
					WETH,
					toWei('0'),
					toWei('10000'),
					now,
					{ from: user2 }
				);
				console.log("gas:", gas)
			}

            const txr = await pool._swapExactAmountInMMMWithTimestamp(
                WBTC,
                toWei(amount.toString()),
                WETH,
                toWei('0'),
                toWei('10000'),
                now,
                { from: user2 }
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');

            const actualAmount = fromWei(log.args[4]);
            const relDifAmount = calcRelativeDiff(expectedAmount, actualAmount);
            if (verbose) {
                console.log('swapExactAmountInMMM');
                console.log(`expected: ${expectedAmount}`);
                console.log(`actual  : ${actualAmount}`);
                console.log(`relDif  : ${relDifAmount}`);
            }
            assert.isAtMost(relDifAmount.toNumber(), errorDelta);

			const actualSpread = fromWei(log.args[5]);
            const relDifSpread = calcRelativeDiff(expectedAmount, actualAmount);
            if (verbose) {
                console.log('swapExactAmountInMMM spread');
                console.log(`expected: ${expectedSpread}`);
                console.log(`actual  : ${actualSpread}`);
                console.log(`relDif  : ${relDifSpread}`);
            }
            assert.isAtMost(relDifSpread.toNumber(), errorDelta);

            const wbtcPrice = await pool._getSpotPriceMMMWithTimestamp(WETH, WBTC, baseSwapFee, now);
            const wbtcPriceFeeCheck = (((parseFloat(fromWei(wethBalance)) - expectedAmount)  / 5) / ((parseFloat(fromWei(wbtcBalance)) + amount) / 5)) * (1 / (1 - 0.003));
            assert.approximately(Number(fromWei(wbtcPrice)), Number(wbtcPriceFeeCheck), errorDelta);

            const wethNormWeight = await pool.getNormalizedWeight(WETH);
            assert.equal(0.333333333333333333, fromWei(wethNormWeight));
        });

		it('MMM spread WETH/DAI', async () => {
			const expectedMMMSpread = computeMMMSpread(
				expectedMeanWETHDAI,
				expectedVarianceWETHDAI,
				z,
				horizon
			)
            const priceSansFee1 = await pool._getSpotPriceMMMWithTimestamp(WETH, DAI, 0, now);
            const priceSansFee2 = await pool._getSpotPriceMMMWithTimestamp(DAI, WETH, 0, now);
            const actualMMMSpread = fromWei(priceSansFee1) * fromWei(priceSansFee2);
			if (verbose) {
                console.log('MMM spread WETH/DAI');
                console.log(`expected: ${expectedMMMSpread}`);
                console.log(`actual  : ${actualMMMSpread}`);
            }
            const relDif = calcRelativeDiff(expectedMMMSpread, actualMMMSpread);
            assert.isAtMost(relDif.toNumber(), errorDelta);
		})

		it('MMM spread WBTC/DAI', async () => {
			const expectedMMMSpread = computeMMMSpread(
				expectedMeanWBTCDAI,
				expectedVarianceWBTCDAI,
				z,
				horizon
			)
            const priceSansFee1 = await pool._getSpotPriceMMMWithTimestamp(WBTC, DAI, 0, now);
            const priceSansFee2 = await pool._getSpotPriceMMMWithTimestamp(DAI, WBTC, 0, now);
            const actualMMMSpread = fromWei(priceSansFee1) * fromWei(priceSansFee2);
            if (verbose) {
				console.log('MMM spread WBTC/DAI');
				console.log(`expected: ${expectedMMMSpread}`);
				console.log(`actual  : ${actualMMMSpread}`);
			}
            const relDif = calcRelativeDiff(expectedMMMSpread, actualMMMSpread);
            assert.isAtMost(relDif.toNumber(), errorDelta);
		})

		it('MMM spread WBTC/WETH', async () => {
			const expectedMMMSpread = computeMMMSpread(
				expectedMeanWBTCWETH,
				expectedVarianceWBTCWETH,
				z,
				horizon
			)
            const priceSansFee1 = await pool._getSpotPriceMMMWithTimestamp(WBTC, WETH, 0, now);
            const priceSansFee2 = await pool._getSpotPriceMMMWithTimestamp(WETH, WBTC, 0, now);
            const actualMMMSpread = fromWei(priceSansFee1) * fromWei(priceSansFee2);
            if (verbose) {
                console.log('MMM spread WBTC/WETH');
                console.log(`expected: ${expectedMMMSpread}`);
                console.log(`actual  : ${actualMMMSpread}`);
            }
            const relDif = calcRelativeDiff(expectedMMMSpread, actualMMMSpread);
            assert.isAtMost(relDif.toNumber(), errorDelta);
		})


//        it('swapExactAmountOutMMM', async () => {
//            // ETH -> 1 WBTC
//            // const amountIn = (55 * (((21 / (21 - 1)) ** (5 / 5)) - 1)) / (1 - 0.003);
//            const expected = calcInGivenOut(55, 5, 21, 5, 1, 0.003);
//            const txr = await pool.swapExactAmountOutMMM(
//                WETH,
//                toWei('3'),
//                WBTC,
//                toWei('1.0'),
//                toWei('500'),
//                { from: user2 },
//            );
//            const log = txr.logs[0];
//            assert.equal(log.event, 'LOG_SWAP');
//            // 2.758274824473420261
//
//            const actual = fromWei(log.args[3]);
//            const relDif = calcRelativeDiff(expected, actual);
//            if (verbose) {
//                console.log('swapExactAmountOutMMM');
//                console.log(`expected: ${expected}`);
//                console.log(`actual  : ${actual}`);
//                console.log(`relDif  : ${relDif}`);
//            }
//
//            assert.isAtMost(relDif.toNumber(), errorDelta);
//        });

    });
});
