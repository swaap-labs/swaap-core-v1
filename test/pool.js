const truffleAssert = require('truffle-assertions');
const { calcOutGivenIn, calcInGivenOut, calcRelativeDiff } = require('../lib/calc_comparisons');

const Pool = artifacts.require('Pool');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');
const verbose = process.env.VERBOSE;

const TConstantOracle = artifacts.require('TConstantOracle');

contract('Pool', async (accounts) => {

	const now = 1641893000;

    const admin = accounts[0];
    const user1 = accounts[1];
    const user2 = accounts[2];
    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const errorDelta = 10 ** -8;
    const MAX = web3.utils.toTwosComplement(-1);

    const z = 1.29;
    const horizon = 3600;
	const priceStatisticsLookbackInRound = 10;
	const priceStatisticsLookbackInSec = 10000;

    let WETH; let MKR; let DAI; let
        XXX; // addresses
    let weth; let mkr; let dai; let
        xxx; // TTokens
    let factory; // Pool factory
    let pool; // first pool w/ defaults
    let POOL; //   pool address

    let wethOracle;
    let mkrOracle;
    let daiOracle;
    let xxxOracle;

    let WETHOracleAddress;
	let MKROracleAddress;
	let DAIOracleAddress;
	let XXXOracleAddress;

    before(async () => {
        factory = await Factory.deployed();

        POOL = await factory.newPool.call();
        await factory.newPool();
        pool = await Pool.at(POOL);

        weth = await TToken.new('Wrapped Ether', 'WETH', 18);
        mkr = await TToken.new('Maker', 'MKR', 18);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18);
        xxx = await TToken.new('XXX', 'XXX', 18);

        WETH = weth.address;
        MKR = mkr.address;
        DAI = dai.address;
        XXX = xxx.address;

		wethOracle = await TConstantOracle.new(200000000000, now);
		mkrOracle = await TConstantOracle.new(50000000000, now);
		daiOracle = await TConstantOracle.new(100000000, now);
		xxxOracle = await TConstantOracle.new(1, now);

        WETHOracleAddress = wethOracle.address;
        MKROracleAddress = mkrOracle.address;
        DAIOracleAddress = daiOracle.address;
        XXXOracleAddress = xxxOracle.address;

        /*
            Tests assume token prices
            WETH - $200
            MKR  - $500
            DAI  - $1
            XXX  - $0
        */

        // Admin balances
        await weth.mint(admin, toWei('50'));
        await mkr.mint(admin, toWei('2000'));
        await dai.mint(admin, toWei('100000'));
        await xxx.mint(admin, toWei('10'));

        // User1 balances
        await weth.mint(user1, toWei('25'), { from: admin });
        await mkr.mint(user1, toWei('100'), { from: admin });
        await dai.mint(user1, toWei('5000'), { from: admin });
        await xxx.mint(user1, toWei('10'), { from: admin });

        // User2 balances
        await weth.mint(user2, toWei('12.2222'), { from: admin });
        await mkr.mint(user2, toWei('1.015333'), { from: admin });
        await dai.mint(user2, toWei('0'), { from: admin });
        await xxx.mint(user2, toWei('51'), { from: admin });
    });

    describe('Binding Tokens', () => {
        it('Controller is msg.sender', async () => {
            const controller = await pool.getController();
            assert.equal(controller, admin);
        });

        it('Pool starts with no bound tokens', async () => {
            const numTokens = await pool.getNumTokens();
            assert.equal(0, numTokens);
            const isBound = await pool.isBound.call(WETH);
            assert(!isBound);
        });

        it('Fails binding tokens that are not approved', async () => {
            await truffleAssert.reverts(
                pool.bindMMM(MKR, toWei('10'), toWei('2.5'), MKROracleAddress),
                'ERR_POOL_TOKEN_BAD_CALLER',
            );
        });

        it('Admin approves tokens', async () => {
            await weth.approve(POOL, MAX);
            await mkr.approve(POOL, MAX);
            await dai.approve(POOL, MAX);
            await xxx.approve(POOL, MAX);
        });

        it('Fails binding weights and balances outside MIX MAX', async () => {
            await truffleAssert.reverts(
                pool.bindMMM(WETH, toWei('51'), toWei('1'), WETHOracleAddress),
                'ERR_INSUFFICIENT_SP',
            );
            await truffleAssert.reverts(
                pool.bindMMM(MKR, toWei('0.0000000000001'), toWei('1'), MKROracleAddress),
                '32',
            );
            await truffleAssert.reverts(
                pool.bindMMM(DAI, toWei('1000'), toWei('0.99'), DAIOracleAddress),
                '30',
            );
            await truffleAssert.reverts(
                pool.bindMMM(WETH, toWei('5'), toWei('50.01'), XXXOracleAddress),
                '31',
            );
        });

        it('Fails finalizing pool without 2 tokens', async () => {
            await truffleAssert.reverts(
                pool.finalize(),
                '18',
            );
        });

        it('Admin binds tokens', async () => {
            // Equal weights WETH, MKR, DAI
            await pool.bindMMM(WETH, toWei('50'), toWei('5'), WETHOracleAddress);
            await pool.bindMMM(MKR, toWei('2000'), toWei('5'), MKROracleAddress);
            await pool.bindMMM(DAI, toWei('100000'), toWei('5'), DAIOracleAddress);
            const numTokens = await pool.getNumTokens();
            assert.equal(3, numTokens);
            const totalDenormWeight = await pool.getTotalDenormalizedWeight();
            assert.equal(15, fromWei(totalDenormWeight));
            const wethDenormWeight = await pool.getDenormalizedWeight(WETH);
            assert.equal(5, fromWei(wethDenormWeight));
            const wethNormWeight = await pool.getNormalizedWeight(WETH);
            assert.equal(0.333333333333333333, fromWei(wethNormWeight));
            const mkrBalance = await pool.getBalance(MKR);
            assert.equal(2000, fromWei(mkrBalance));
        });

        it('Admin unbinds token', async () => {
            await pool.bindMMM(XXX, toWei('10'), toWei('5'), XXXOracleAddress);
            let adminBalance = await xxx.balanceOf(admin);
            assert.equal(0, fromWei(adminBalance));
            await pool.unbindMMM(XXX);
            adminBalance = await xxx.balanceOf(admin);
            assert.equal(10, fromWei(adminBalance));
            const numTokens = await pool.getNumTokens();
            assert.equal(3, numTokens);
            const totalDenormWeight = await pool.getTotalDenormalizedWeight();
            assert.equal(15, fromWei(totalDenormWeight));
        });

        it('Fails binding above MAX TOTAL WEIGHT', async () => {
            await truffleAssert.reverts(
                pool.bindMMM(XXX, toWei('1'), toWei('40'), XXXOracleAddress),
                '33',
            );
        });

        it('Fails rebinding token or unbinding random token', async () => {
            await truffleAssert.reverts(
                pool.bindMMM(WETH, toWei('0'), toWei('1'), WETHOracleAddress),
                '28',
            );
            await truffleAssert.reverts(
                pool.rebindMMM(XXX, toWei('0'), toWei('1'), XXXOracleAddress),
                '2',
            );
            await truffleAssert.reverts(
                pool.unbindMMM(XXX),
                '2',
            );
        });

        it('Get current tokens', async () => {
            const currentTokens = await pool.getCurrentTokens();
            assert.sameMembers(currentTokens, [WETH, MKR, DAI]);
        });

        it('Fails getting final tokens before finalized', async () => {
            await truffleAssert.reverts(
                pool.getFinalTokens(),
                '1',
            );
        });
    });


    describe('Finalizing pool', () => {
        it('Fails when other users interact before finalizing', async () => {
            await truffleAssert.reverts(
                pool.bindMMM(WETH, toWei('5'), toWei('5'), WETHOracleAddress, { from: user1 }),
                '3',
            );
            await truffleAssert.reverts(
                pool.rebindMMM(WETH, toWei('5'), toWei('5'), WETHOracleAddress, { from: user1 }),
                '3',
            );
            await truffleAssert.reverts(
                pool.joinPool(toWei('1'), [MAX, MAX], { from: user1 }),
                '1',
            );
            await truffleAssert.reverts(
                pool.exitPool(toWei('1'), [toWei('0'), toWei('0')], { from: user1 }),
                '1',
            );
            await truffleAssert.reverts(
                pool.unbindMMM(DAI, { from: user1 }),
                '3',
            );
        });

        it('Fails calling any swap before finalizing', async () => {
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(WETH, toWei('2.5'), DAI, toWei('475'), toWei('200')),
                '10',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(DAI, toWei('2.5'), WETH, toWei('475'), toWei('200')),
                '10',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(WETH, toWei('2.5'), DAI, toWei('475'), toWei('200')),
                '10',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(DAI, toWei('2.5'), WETH, toWei('475'), toWei('200')),
                '10',
            );
        });

        it('Fails calling any join exit swap before finalizing', async () => {
            await truffleAssert.reverts(
                pool.joinswapExternAmountInMMM(WETH, toWei('2.5'), toWei('0')),
                '1',
            );
            await truffleAssert.reverts(
                pool.joinswapPoolAmountOutMMM(WETH, toWei('2.5'), MAX),
                '1',
            );
            await truffleAssert.reverts(
                pool.exitswapPoolAmountInMMM(WETH, toWei('2.5'), toWei('0')),
                '1',
            );
            await truffleAssert.reverts(
                pool.exitswapExternAmountOutMMM(WETH, toWei('2.5'), MAX),
                '1',
            );
        });

        it('Only controller can setPublicSwap', async () => {
            await pool.setPublicSwap(true);
            const publicSwap = pool.isPublicSwap();
            assert(publicSwap);
            await truffleAssert.reverts(pool.setPublicSwap(true, { from: user1 }), '3');
        });

        it('Fails setting low swap fees', async () => {
            await truffleAssert.reverts(
                pool.setSwapFee(toWei('0.0000001')),
                '14',
            );
        });

        it('Fails setting high swap fees', async () => {
            await truffleAssert.reverts(
                pool.setSwapFee(toWei('0.11')),
                '15',
            );
        });

        it('Fails nonadmin sets fees or controller', async () => {
            await truffleAssert.reverts(
                pool.setSwapFee(toWei('0.003'), { from: user1 }),
                '3',
            );
            await truffleAssert.reverts(
                pool.setController(user1, { from: user1 }),
                '3',
            );
        });

        it('Admin sets swap fees', async () => {
            await pool.setSwapFee(toWei('0.003'));
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
        });

        it('Fails nonadmin finalizes pool', async () => {
            await truffleAssert.reverts(
                pool.finalize({ from: user1 }),
                '3',
            );
        });

        it('Admin finalizes pool', async () => {
            const tx = await pool.finalize();
            const adminBal = await pool.balanceOf(admin);
            assert.equal(fromWei(adminBal), fromWei(adminBal));
//            truffleAssert.eventEmitted(tx, 'Transfer', (event) => event.dst === admin);
            const finalized = pool.isFinalized();
            assert(finalized);
        });

        it('Fails finalizing pool after finalized', async () => {
            await truffleAssert.reverts(
                pool.finalize(),
                '4',
            );
        });

        it('Cant setPublicSwap, setSwapFee when finalized', async () => {
            await truffleAssert.reverts(pool.setPublicSwap(false), '4');
            await truffleAssert.reverts(pool.setSwapFee(toWei('0.01')), '4');
        });

        it('Fails binding new token after finalized', async () => {
            await truffleAssert.reverts(
                pool.bindMMM(XXX, toWei('10'), toWei('5'), XXXOracleAddress),
                '4',
            );
            await truffleAssert.reverts(
                pool.rebindMMM(DAI, toWei('10'), toWei('5'), DAIOracleAddress),
                '4',
            );
        });

        it('Fails unbinding after finalized', async () => {
            await truffleAssert.reverts(
                pool.unbindMMM(WETH),
                '4',
            );
        });

        it('Get final tokens', async () => {
            const finalTokens = await pool.getFinalTokens();
            assert.sameMembers(finalTokens, [WETH, MKR, DAI]);
        });
    });

    describe('User interactions', () => {
        it('Other users approve tokens', async () => {
            await weth.approve(POOL, MAX, { from: user1 });
            await mkr.approve(POOL, MAX, { from: user1 });
            await dai.approve(POOL, MAX, { from: user1 });
            await xxx.approve(POOL, MAX, { from: user1 });

            await weth.approve(POOL, MAX, { from: user2 });
            await mkr.approve(POOL, MAX, { from: user2 });
            await dai.approve(POOL, MAX, { from: user2 });
            await xxx.approve(POOL, MAX, { from: user2 });
        });

        it('Fail swaps when Factory is paused', async () => {
            await factory.setPause(true, {from: admin});
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(WETH, toWei('2.5'), DAI, toWei('475'), toWei('200'), { from: user2 }),
                '36'
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(WETH, toWei('2.5'), DAI, toWei('475'), toWei('200'), { from: user2 }),
                 '36'
            );               
        });

        it('Fail User1 join/joinswap when Factory is paused', async () => {
            await truffleAssert.reverts(pool.joinPool(toWei('5'), [MAX, MAX, MAX], { from: user1 }), '36');
            await truffleAssert.reverts(pool.joinswapPoolAmountOutMMM.call(WETH, toWei('0.01'), MAX), '36');
            await truffleAssert.reverts(pool.joinswapExternAmountInMMM.call(WETH, toWei('0.1'), toWei('0')), '36');
        });

        it('Admin unpauses pool', async () => {
            await factory.setPause(false, {from: admin});
        })

        it('User1 joins pool', async () => {
            await pool.joinPool(toWei('5'), [MAX, MAX, MAX], { from: user1 });
            const daiBalance = await pool.getBalance(DAI);
            assert.equal(105000, fromWei(daiBalance));
            const userWethBalance = await weth.balanceOf(user1);
            assert.equal(22.5, fromWei(userWethBalance));
        });

        /*
          Current pool balances
          WETH - 52.5
          MKR - 21
          DAI - 10,500
          XXX - 0
        */

        it('Fails admin unbinding token after finalized and others joined', async () => {
            await truffleAssert.reverts(pool.unbindMMM(DAI), '4');
        });

        it('getSpotPriceSansFeeMMM and getSpotPrice', async () => {
            const wethPrice = await pool.getSpotPriceSansFeeMMM(DAI, WETH);
            assert.equal(2000, fromWei(wethPrice));

            const wethPriceFee = await pool.getSpotPriceMMM(DAI, WETH);
            const wethPriceFeeCheck = ((105000 / 5) / (52.5 / 5)) * (1 / (1 - 0.003));
            assert.equal(fromWei(wethPriceFee), wethPriceFeeCheck);
        });

        it('Fail swapExactAmountInMMM unbound or over min max ratios', async () => {
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(WETH, toWei('2.5'), XXX, toWei('100'), toWei('200'), { from: user2 }),
                '2',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(WETH, toWei('26.5'), DAI, toWei('5000'), toWei('200'), { from: user2 }),
                '44',
            );
        });

        it('swapExactAmountInMMM', async () => {
            // 0.025 WETH -> DAI
            const expected = calcOutGivenIn(52.5, 5, 105000, 5, 0.025, 0.003);
            const txr = await pool.swapExactAmountInMMM(
                WETH,
                toWei('0.025'),
                DAI,
                toWei('49'),
                toWei('0.00051'),
                { from: user2 },
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');

            const actual = fromWei(log.args[4]);
            const relDif = calcRelativeDiff(expected, actual);
            if (verbose) {
                console.log('swapExactAmountInMMM');
                console.log(`expected: ${expected}`);
                console.log(`actual  : ${actual}`);
                console.log(`relDif  : ${relDif}`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            const userDaiBalance = await dai.balanceOf(user2);
            assert.equal(fromWei(userDaiBalance), Number(fromWei(log.args[4])));

            // 182.804672101083406128
            const wethPrice = await pool.getSpotPriceMMM(DAI, WETH);
            const wethPriceFeeCheck = ((104950.173656 / 5) / (52.525 / 5)) * (1 / (1 - 0.003));
            assert.approximately(Number(fromWei(wethPrice)), Number(wethPriceFeeCheck), errorDelta);

            const daiNormWeight = await pool.getNormalizedWeight(DAI);
            assert.equal(0.333333333333333333, fromWei(daiNormWeight));
        });

        it('swapExactAmountOut', async () => {
            // WETH -> 1 MKR
            // const amountIn = (52.525 * (((2100 / (2100 - 1)) ** (5 / 5)) - 1)) / (1 - 0.003);
            const expected = calcInGivenOut(52.525, 5, 2100, 5, 1, 0.003);
            const txr = await pool.swapExactAmountOutMMM(
                WETH,
                toWei('0.026'),
                MKR,
                toWei('1.0'),
                toWei('0.027'),
                { from: user2 },
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');

            const actual = fromWei(log.args[3]);
            const relDif = calcRelativeDiff(expected, actual);
            if (verbose) {
                console.log('swapExactAmountOut');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('Fails joins exits with limits', async () => {
            await truffleAssert.reverts(
                pool.joinPool(toWei('10'), [toWei('1'), toWei('1'), toWei('1')]),
                '8',
            );

            await truffleAssert.reverts(
                pool.exitPool(toWei('10'), [toWei('10'), toWei('1000'), toWei('10000')]),
                '9',
            );

            await truffleAssert.reverts(
                pool.joinswapExternAmountInMMM(DAI, toWei('1000'), toWei('10')),
                '9',
            );

            await truffleAssert.reverts(
                pool.joinswapPoolAmountOutMMM(DAI, toWei('10'), toWei('100')),
                '8',
            );

            await truffleAssert.reverts(
                pool.exitswapPoolAmountInMMM(DAI, toWei('1'), toWei('10000')),
                '9',
            );

            await truffleAssert.reverts(
                pool.exitswapExternAmountOutMMM(DAI, toWei('10000'), toWei('1')),
                '8',
            );
        });

        it('Fails calling any swap on unbound token', async () => {
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(XXX, toWei('2.5'), DAI, toWei('475'), toWei('200')),
                '2',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(DAI, toWei('2.5'), XXX, toWei('475'), toWei('200')),
                '2',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(XXX, toWei('2.5'), DAI, toWei('475'), toWei('200')),
                '2',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(DAI, toWei('2.5'), XXX, toWei('475'), toWei('200')),
                '2',
            );
            await truffleAssert.reverts(
                 pool.joinswapExternAmountInMMM(XXX, toWei('2.5'), toWei('0')),
                '2',
            );
            await truffleAssert.reverts(
                pool.joinswapPoolAmountOutMMM(XXX, toWei('2.5'), MAX),
                '2',
            );
            await truffleAssert.reverts(
                pool.exitswapPoolAmountInMMM(XXX, toWei('2.5'), toWei('0')),
                '2',
            );
            await truffleAssert.reverts(
                pool.exitswapExternAmountOutMMM(XXX, toWei('2.5'), MAX),
                '2',
            );
        });

        it('Fails calling weights, balances, spot prices on unbound token', async () => {
            await truffleAssert.reverts(
                pool.getDenormalizedWeight(XXX),
                '2',
            );
            await truffleAssert.reverts(
                pool.getNormalizedWeight(XXX),
                '2',
            );
            await truffleAssert.reverts(
                pool.getBalance(XXX),
                '2',
            );
            await truffleAssert.reverts(
                pool.getSpotPriceMMM(DAI, XXX),
                '2',
            );
            await truffleAssert.reverts(
                pool.getSpotPriceMMM(XXX, DAI),
                '2',
            );
            await truffleAssert.reverts(
                pool.getSpotPriceSansFeeMMM(DAI, XXX),
                '2',
            );
            await truffleAssert.reverts(
                pool.getSpotPriceSansFeeMMM(XXX, DAI),
                '2',
            );
        });
    });

    describe('Token interactions', () => {
        it('Token descriptors', async () => {
            const name = await pool.name();
            assert.equal(name, 'Swaap Pool Token');

            const symbol = await pool.symbol();
            assert.equal(symbol, 'SPT');

            const decimals = await pool.decimals();
            assert.equal(decimals, 18);
        });

        it('Token allowances', async () => {
            await pool.approve(user1, toWei('50'));
            let allowance = await pool.allowance(admin, user1);
            assert.equal(fromWei(allowance), 50);

            await pool.increaseApproval(user1, toWei('50'));
            allowance = await pool.allowance(admin, user1);
            assert.equal(fromWei(allowance), 100);

            await pool.decreaseApproval(user1, toWei('50'));
            allowance = await pool.allowance(admin, user1);
            assert.equal(fromWei(allowance), 50);

            await pool.decreaseApproval(user1, toWei('100'));
            allowance = await pool.allowance(admin, user1);
            assert.equal(fromWei(allowance), 0);
        });

        it('Token transfers', async () => {
            await truffleAssert.reverts(
                pool.transferFrom(user2, admin, toWei('10')),
                '',
            );

            await pool.transferFrom(admin, user2, toWei('1'));
            await pool.approve(user2, toWei('10'));
            await pool.transferFrom(admin, user2, toWei('1'), { from: user2 });
        });
    });
});
