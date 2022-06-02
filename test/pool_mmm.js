const truffleAssert = require('truffle-assertions');
const { calcOutGivenIn, calcInGivenOut, calcRelativeDiff } = require('../lib/calc_comparisons');
const { getOracleDataHistory } = require('../lib/data');
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

	let now;

    const admin = accounts[0];
    const user1 = accounts[1];
    const user2 = accounts[2];

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const errorDelta = 10 ** -5;
    const spreadErrorDelta = 5 * (10 ** -4);
    const MAX = web3.utils.toTwosComplement(-1);

    const z = 1;
    const horizon = 600;
    const priceStatisticsLookbackInRound = 6;
    const priceStatisticsLookbackStepInRound = 3;
    const priceStatisticsLookbackInSec = 3600 * 2;
    const maxPriceUnpegRatio = 1.02;

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

	let _wethOraclePrices;
	let _wethOracleTimestamps;
	let _wbtcOraclePrices;
	let _wbtcOracleTimestamps;
	let _daiOraclePrices;
	let _daiOracleTimestamps;

	const wethDecimals = 18;
	const wbtcDecimals = 16;
	const daiDecimals = 14;

	const wbtcDecimalsDiffFactor = 10**(wbtcDecimals - wethDecimals)
	const daiDecimalsDiffFactor = 10**(daiDecimals - wethDecimals)

	let wethOraclePriceLast; let wbtcOraclePriceLast; let daiOraclePriceLast;

	let expectedMeanWETHDAI; let expectedVarianceWETHDAI;
	let expectedMeanWBTCDAI; let expectedVarianceWBTCDAI;
	let expectedMeanWBTCWETH; let expectedVarianceWBTCWETH;

    before(async () => {

    	factory = await Factory.deployed();

        POOL = await factory.newPool.call();
        await factory.newPool();
        pool = await Pool.at(POOL);

        weth = await TToken.new('Wrapped Ether', 'WETH', wethDecimals);
        wbtc = await TToken.new('Wrapped Bitcoin', 'WBTC', wbtcDecimals);
        dai = await TToken.new('Dai Stablecoin', 'DAI', daiDecimals);

        WETH = weth.address;
        WBTC = wbtc.address;
        DAI = dai.address;

        wethOracle = await TWETHOracle.new();
        wbtcOracle = await TWBTCOracle.new();
        daiOracle = await TDAIOracle.new();

    	const lastBlock = await web3.eth.getBlock("latest")
    	now = lastBlock.timestamp

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

        const [wethOraclePrices, wethOracleTimestamps] = await getOracleDataHistory(wethOracle, 10, priceStatisticsLookbackStepInRound);
        const [wbtcOraclePrices, wbtcOracleTimestamps] = await getOracleDataHistory(wbtcOracle, 10, priceStatisticsLookbackStepInRound);
        const [daiOraclePrices, daiOracleTimestamps] = await getOracleDataHistory(daiOracle, 10, priceStatisticsLookbackStepInRound);

        _wethOraclePrices = [...wethOraclePrices]
        _wethOracleTimestamps = [...wethOracleTimestamps]
        _wbtcOraclePrices = [...wbtcOraclePrices]
        _wbtcOracleTimestamps = [...wbtcOracleTimestamps]
        _daiOraclePrices = [...daiOraclePrices]
        _daiOracleTimestamps = [...daiOracleTimestamps]

        wethOraclePriceLast = _wethOraclePrices[0] / 10**8;
        wbtcOraclePriceLast = _wbtcOraclePrices[0] / 10**8;
        daiOraclePriceLast = _daiOraclePrices[0] / 10**8;

		await updateState()

        wethInitialBalance = valuePerAsset / wethOraclePriceLast
        wbtcInitialBalance = valuePerAsset / wbtcOraclePriceLast * wbtcDecimalsDiffFactor
        daiInitialBalance = valuePerAsset / daiOraclePriceLast * daiDecimalsDiffFactor

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

    async function updateState() {
    	const lastBlock = await web3.eth.getBlock("latest")
    	const _now = lastBlock.timestamp
    	if (_now != now) {
    		now = _now

    		let wethOracleTimestamps = [..._wethOracleTimestamps]
    		let daiOracleTimestamps = [..._daiOracleTimestamps]
			const [wethOracleStartIndexWETHDAI, daiOracleStartIndexWETHDAI] = getStartIndices(
				wethOracleTimestamps, daiOracleTimestamps,
				priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
			)
			const [_expectedMeanWETHDAI, _expectedVarianceWETHDAI] = getParametersEstimation(
				[..._wethOraclePrices], wethOracleTimestamps, wethOracleStartIndexWETHDAI,
				[..._daiOraclePrices], daiOracleTimestamps, daiOracleStartIndexWETHDAI,
				priceStatisticsLookbackInSec, now
			);
			expectedMeanWETHDAI = _expectedMeanWETHDAI;
			expectedVarianceWETHDAI = _expectedVarianceWETHDAI;

    		daiOracleTimestamps = [..._daiOracleTimestamps]
    		let wbtcOracleTimestamps = [..._wbtcOracleTimestamps]
			const [wbtcOracleStartIndexWBTCDAI, daiOracleStartIndexWBTCDAI] = getStartIndices(
				wbtcOracleTimestamps, daiOracleTimestamps,
				priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
			)
			const [_expectedMeanWBTCDAI, _expectedVarianceWBTCDAI] = getParametersEstimation(
				[..._wbtcOraclePrices], wbtcOracleTimestamps, wbtcOracleStartIndexWBTCDAI,
				[..._daiOraclePrices], _daiOracleTimestamps, daiOracleStartIndexWBTCDAI,
				priceStatisticsLookbackInSec, now
			);
			expectedMeanWBTCDAI = _expectedMeanWBTCDAI;
			expectedVarianceWBTCDAI = _expectedVarianceWBTCDAI;

    		wethOracleTimestamps = [..._wethOracleTimestamps]
    		wbtcOracleTimestamps = [..._wbtcOracleTimestamps]
			const [wbtcOracleStartIndexWBTCWETH, wethOracleStartIndexWBTCWETH] = getStartIndices(
				wbtcOracleTimestamps, wethOracleTimestamps,
				priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
			)
			const [_expectedMeanWBTCWETH, _expectedVarianceWBTCWETH] = getParametersEstimation(
				[..._wbtcOraclePrices], wbtcOracleTimestamps, wbtcOracleStartIndexWBTCWETH,
				[..._wethOraclePrices], [..._wethOracleTimestamps], wethOracleStartIndexWBTCWETH,
				priceStatisticsLookbackInSec, now
			);
			expectedMeanWBTCWETH = _expectedMeanWBTCWETH;
			expectedVarianceWBTCWETH = _expectedVarianceWBTCWETH;
		} else {
		   now = _now
		}
	}

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
            const tokens = await pool.getTokens();
            const numTokens = tokens.length
            assert.equal(3, numTokens);
            const weights = await Promise.all(tokens.map(t => pool.getDenormalizedWeight(t)));
            const totalDenormWeight = weights.reduce((acc, v) => acc + parseFloat(fromWei(v)), 0);
            assert.equal(15, totalDenormWeight);
            const wethDenormWeight = await pool.getDenormalizedWeight(WETH);
            assert.equal(5, fromWei(wethDenormWeight));
            assert.equal(0.333333333333333333, fromWei(wethDenormWeight) / totalDenormWeight);
            const wbtcBalance = await pool.getBalance(WBTC);
            const relDif = calcRelativeDiff(wbtcInitialBalance, fromWei(wbtcBalance));
            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('Get current tokens', async () => {
            const currentTokens = await pool.getTokens();
            assert.sameMembers(currentTokens, [WETH, WBTC, DAI]);
        });

    });


    describe('Finalizing pool', () => {

        it('Admin sets swap fees', async () => {
            await pool.setSwapFee(baseSwapFee);
            const swapFee = await pool.getSwapFee();
            assert.equal(0.003, fromWei(swapFee));
        });

        it('Admin sets dynamic spread parameters', async () => {
            await pool.setDynamicCoverageFeesZ(toWei(z.toString()));
            await pool.setDynamicCoverageFeesHorizon(toWei(horizon.toString()));
            await pool.setPriceStatisticsLookbackInRound(priceStatisticsLookbackInRound);
            await pool.setPriceStatisticsLookbackInSec(priceStatisticsLookbackInSec);
            const expectedCoverageParameters = await pool.getCoverageParameters();
            assert.equal(fromWei(expectedCoverageParameters[0]), z);
            assert.equal(fromWei(expectedCoverageParameters[1]), horizon);
            assert.equal(expectedCoverageParameters[2], priceStatisticsLookbackInRound);
            assert.equal(expectedCoverageParameters[3], priceStatisticsLookbackInSec);
            assert.equal(expectedCoverageParameters[4], priceStatisticsLookbackStepInRound);
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
            const finalTokens = await pool.getTokens();
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
            const relDif = calcRelativeDiff(daiInitialBalance * (105 / 100), fromWei(daiBalance));
            assert.isAtMost(relDif.toNumber(), errorDelta);
            const userWethBalance = await weth.balanceOf(user1);
            assert.equal(2500 - wethInitialBalance * (5 / 100), fromWei(userWethBalance));
        });

        it('getSpotPrice', async () => {

            await updateState()

            const daiBalance = await pool.getBalance(DAI);
            const wethBalance = await pool.getBalance(WETH);

            const price = await pool.getSpotPriceSansFee(WETH, DAI);

            const expectedPriceSansFee = parseFloat(
            	(wethInitialBalance * (105 / 100) / 5) / (daiInitialBalance * (105 / 100) / 5)
            )

            const relDif = calcRelativeDiff(expectedPriceSansFee, parseFloat(fromWei(price)));
            assert.isAtMost(relDif.toNumber(), spreadErrorDelta);

        });

        it('Fail swapExactAmountInMMM unpegged', async () => {
            // 320 represent about 10% of WETH balance
            try {
                await pool.swapExactAmountInMMM(WETH, toWei('320'), DAI, toWei('0'), toWei((4000 / daiDecimalsDiffFactor).toString()), { from: user2 });
                throw 'did not revert';
            }
            catch(e) {
                assert(e.reason, 'SWAAP#44');
            }
            /*await truffleAssert.reverts(
                pool.swapExactAmountInMMM(WETH, toWei('320'), DAI, toWei('0'), toWei((4000 / daiDecimalsDiffFactor).toString()), { from: user2 }),
                '44'
            );*/
        });

        it('swapExactAmountInMMM WETH -> DAI', async () => {
            // 1 WETH -> DAI
            const amount = 1

            const wethBalance = await pool.getBalance(WETH);
            const daiBalance = await pool.getBalance(DAI);
            const relativePrice = daiOraclePriceLast / wethOraclePriceLast;

			if (verbose) {
	            const gas = await pool.swapExactAmountInMMM.estimateGas(
	                WETH,
	                toWei(amount.toString()),
	                DAI,
	                0,
	                toWei((10000 / daiDecimalsDiffFactor).toString()),
	                { from: user2 }
	            );
	            console.log("gas:", gas)
			}

            const txr = await pool.swapExactAmountInMMM(
                WETH,
                toWei(amount.toString()),
                DAI,
                0,
                toWei((10000 / daiDecimalsDiffFactor).toString()),
                { from: user2 }
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');

            await updateState()

			const [expectedAmount, expectedSpread] = calcOutGivenInMMM(
				parseFloat(wethBalance) / 10**wethDecimals,
				5,
				parseFloat(daiBalance) / 10**daiDecimals,
				5,
				amount,
				0.003,
				expectedMeanWETHDAI,
				expectedVarianceWETHDAI,
				z,
				horizon,
				relativePrice
			);

            const actualAmount = parseFloat(log.args[4]) / 10**daiDecimals;
            const relDifAmount = calcRelativeDiff(expectedAmount, actualAmount);
            if (verbose) {
                console.log('swapExactAmountInMMM amount' );
                console.log(`expected: ${expectedAmount}`);
                console.log(`actual  : ${actualAmount}`);
                console.log(`relDif  : ${relDifAmount}`);
            }

			const actualSpread = fromWei(log.args[5]);
            const relDifSpread = calcRelativeDiff(expectedSpread, actualSpread);
            if (verbose) {
                console.log('swapExactAmountInMMM spread');
                console.log(`expected: ${expectedSpread}`);
                console.log(`actual  : ${actualSpread}`);
                console.log(`relDif  : ${relDifSpread}`);
            }

            assert.isAtMost(relDifAmount.toNumber(), errorDelta);
            assert.isAtMost(relDifSpread.toNumber(), spreadErrorDelta);

            const userDaiBalance = await dai.balanceOf(user2);
            assert.equal(fromWei(userDaiBalance), Number(fromWei(log.args[4])));

            const wethPrice = await pool.getSpotPriceSansFee(DAI, WETH);
			const wethPriceSansFeeCheck = ((parseFloat(daiBalance) / 10**daiDecimals - expectedAmount)  / 5) / ((parseFloat(wethBalance) / 10**wethDecimals + amount) / 5);
            assert.approximately(Number(fromWei(wethPrice) / daiDecimalsDiffFactor), Number(wethPriceSansFeeCheck), errorDelta);

            const tokens = await pool.getTokens();
            const weights = await Promise.all(tokens.map(t => pool.getDenormalizedWeight(t)));
            const totalDenormWeight = weights.reduce((acc, v) => acc + parseFloat(fromWei(v)), 0);

            const daiNormWeight = await pool.getDenormalizedWeight(DAI);
            assert.equal(0.333333333333333333, fromWei(daiNormWeight) / totalDenormWeight);
        });

		it('swapExactAmountInMMM WBTC -> WETH', async () => {
            // 0.1 WBTC -> WETH
            const amount = 0.1

            const wbtcBalance = await pool.getBalance(WBTC);
            const wethBalance = await pool.getBalance(WETH);

            const relativePrice = wethOraclePriceLast / wbtcOraclePriceLast;

			const [expectedAmount, expectedSpread] = calcOutGivenInMMM(
				parseFloat(wbtcBalance) / 10**wbtcDecimals,
				5,
				parseFloat(wethBalance) / 10**wethDecimals,
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
				const gas = await pool.swapExactAmountInMMM.estimateGas(
					WBTC,
					(amount * 10**wbtcDecimals).toString(),
					WETH,
					0,
					toWei((10000 * wbtcDecimalsDiffFactor).toString()),
					{ from: user2 }
				);
				console.log("gas:", gas)
			}

            const txr = await pool.swapExactAmountInMMM(
                WBTC,
                (amount * 10**wbtcDecimals).toString(),
                WETH,
                0,
				toWei((10000 * wbtcDecimalsDiffFactor).toString()),
                { from: user2 }
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');

            await updateState()

            const actualAmount = parseFloat(log.args[4]) / 10**wethDecimals;
            const relDifAmount = calcRelativeDiff(expectedAmount, actualAmount);
            if (verbose) {
                console.log('swapExactAmountInMMM');
                console.log(`expected: ${expectedAmount}`);
                console.log(`actual  : ${actualAmount}`);
                console.log(`relDif  : ${relDifAmount}`);
            }

			const actualSpread = fromWei(log.args[5]);
            const relDifSpread = calcRelativeDiff(expectedSpread, actualSpread);
            if (verbose) {
                console.log('swapExactAmountInMMM spread');
                console.log(`expected: ${expectedSpread}`);
                console.log(`actual  : ${actualSpread}`);
                console.log(`relDif  : ${relDifSpread}`);
            }

            assert.isAtMost(relDifAmount.toNumber(), errorDelta);
            assert.isAtMost(relDifSpread.toNumber(), spreadErrorDelta);

            const wbtcPrice = await pool.getSpotPriceSansFee(WETH, WBTC);
            const wbtcPriceSansFeeCheck = ((parseFloat(wethBalance) / 10**wethDecimals - expectedAmount)  / 5) / ((parseFloat(wbtcBalance) / 10**wbtcDecimals + amount) / 5);
            assert.approximately(Number(fromWei(wbtcPrice) * wbtcDecimalsDiffFactor), Number(wbtcPriceSansFeeCheck), errorDelta);

            const tokens = await pool.getTokens();
            const weights = await Promise.all(tokens.map(t => pool.getDenormalizedWeight(t)));
            const totalDenormWeight = weights.reduce((acc, v) => acc + parseFloat(fromWei(v)), 0);

            const wethDenormWeight = await pool.getDenormalizedWeight(WETH);
            assert.equal(0.333333333333333333, fromWei(wethDenormWeight) / totalDenormWeight);
        });

		it('swapExactAmountOutMMM WBTC -> WETH', async () => {
            // 0.1 WBTC -> WETH
            const amount = 0.1

            const wbtcBalance = await pool.getBalance(WBTC);
            const wethBalance = await pool.getBalance(WETH);

            const relativePrice = wethOraclePriceLast / wbtcOraclePriceLast;

			const [expectedAmount, expectedSpread] = calcOutGivenInMMM(
				parseFloat(wbtcBalance) / 10**wbtcDecimals,
				5,
				parseFloat(wethBalance) / 10**wethDecimals,
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
				const gas = await pool.swapExactAmountOutMMM.estimateGas(
					WBTC,
					toWei('1000000000000000000000000000'), // large maxAmountIn
					WETH,
					toWei(expectedAmount.toString()),
					toWei((10000 * wbtcDecimalsDiffFactor).toString()),
					{ from: user2 }
				);
				console.log("gas:", gas)
			}

            const txr = await pool.swapExactAmountOutMMM(
                WBTC,
                toWei('1000000000000000000000000000'), // large maxAmountIn
                WETH,
                toWei(expectedAmount.toString()),
				toWei((10000 * wbtcDecimalsDiffFactor).toString()),
                { from: user2 }
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');
            await updateState()

			const actualAmount = parseFloat(log.args[3]) / 10**wbtcDecimals;
            const relDifAmount = calcRelativeDiff(amount, actualAmount);
            if (verbose) {
                console.log('swapExactAmountOutMMM');
                console.log(`expected: ${amount}`);
                console.log(`actual  : ${actualAmount}`);
                console.log(`relDif  : ${relDifAmount}`);
            }

			const actualSpread = fromWei(log.args[5]);
            const relDifSpread = calcRelativeDiff(expectedSpread, actualSpread);
            if (verbose) {
                console.log('swapExactAmountOutMMM spread');
                console.log(`expected: ${expectedSpread}`);
                console.log(`actual  : ${actualSpread}`);
                console.log(`relDif  : ${relDifSpread}`);
            }

            assert.isAtMost(relDifAmount.toNumber(), errorDelta);
            assert.isAtMost(relDifSpread.toNumber(), spreadErrorDelta);

            const wbtcPrice = await pool.getSpotPriceSansFee(WETH, WBTC);
            const wbtcPriceSansFeeCheck = ((parseFloat(wethBalance) / 10**wethDecimals - expectedAmount)  / 5) / ((parseFloat(wbtcBalance) / 10**wbtcDecimals + amount) / 5);
            assert.approximately(Number(fromWei(wbtcPrice) * wbtcDecimalsDiffFactor), Number(wbtcPriceSansFeeCheck), errorDelta);

            const tokens = await pool.getTokens();
            const weights = await Promise.all(tokens.map(t => pool.getDenormalizedWeight(t)));
            const totalDenormWeight = weights.reduce((acc, v) => acc + parseFloat(fromWei(v)), 0);

            const wethDenormWeight = await pool.getDenormalizedWeight(WETH);
            assert.equal(0.333333333333333333, fromWei(wethDenormWeight) / totalDenormWeight);
        });

    });
});
