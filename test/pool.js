const truffleAssert = require('truffle-assertions');
const { calcOutGivenIn, calcInGivenOut, calcRelativeDiff } = require('../lib/calc_comparisons');

const Pool = artifacts.require('Pool');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');
const TTokenWithFees = artifacts.require('TTokenWithFees');

const verbose = process.env.VERBOSE;

const TConstantOracle = artifacts.require('TConstantOracle');

contract('Pool', async (accounts) => {

    const admin = accounts[0];
    const user1 = accounts[1];
    const user2 = accounts[2];
    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const errorDelta = 10 ** -8;
    const MAX = web3.utils.toTwosComplement(-1);

    let WETH; let MKR; let DAI; let
        XXX; let XXXWITHFEES // addresses
    let weth; let mkr; let dai; let
        xxx; let xxxWithFees; // TTokens
    let factory; // Pool factory
    let pool; // first pool w/ defaults
    let POOL; //   pool address

    let wethOracle;
    let mkrOracle;
    let daiOracle;
    let xxxOracle;

    const wethDecimals = 18
    const mkdrDecimals = 8
    const daiDecimals = 6
    const xxxDecimals = 18
    const xxxWithFeesDecimals = 18

    const daiDecimalsDiffFactor = 10**(daiDecimals - wethDecimals)
    const mkrDecimalsDiffFactor = 10**(mkdrDecimals - wethDecimals)

    let WETHOracleAddress;
	let MKROracleAddress;
	let DAIOracleAddress;
	let XXXOracleAddress;

    before(async () => {
        factory = await Factory.deployed();

        POOL = await factory.newPool.call();
        await factory.newPool();
        pool = await Pool.at(POOL);

        weth = await TToken.new('Wrapped Ether', 'WETH', wethDecimals);
        mkr = await TToken.new('Maker', 'MKR', mkdrDecimals);
        dai = await TToken.new('Dai Stablecoin', 'DAI', daiDecimals);
        xxx = await TToken.new('XXX', 'XXX', xxxDecimals);
        xxxWithFees = await TTokenWithFees.new('XXX', 'XXX', xxxWithFeesDecimals);

        WETH = weth.address;
        MKR = mkr.address;
        DAI = dai.address;
        XXX = xxx.address;
        XXXWITHFEES = xxxWithFees.address;

        wethOracle = await TConstantOracle.new((2000 * 10**8).toString());
        mkrOracle = await TConstantOracle.new((50 * 10**8).toString());
        daiOracle = await TConstantOracle.new((1 * 10**8).toString());
        xxxOracle = await TConstantOracle.new((1 * 10**8).toString());

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
        await xxxWithFees.mint(admin, toWei('10'));

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
            const tokens = await pool.getTokens();
            const numTokens = tokens.length
            assert.equal(0, numTokens);
            const isBound = await pool.isBound.call(WETH);
            assert(!isBound);
        });

        it('Fails binding tokens that are not approved', async () => {
            try {
                await pool.bindMMM(MKR, toWei('10'), toWei('2.5'), MKROracleAddress);
                throw 'did not revert';
            }
            catch(e) {
                assert(e.reason, 'ERR_POOL_TOKEN_BAD_CALLER')
            }
            /*await truffleAssert.reverts(
                pool.bindMMM(MKR, toWei('10'), toWei('2.5'), MKROracleAddress),
                'ERR_POOL_TOKEN_BAD_CALLER',
            );*/
        });

        it('Admin approves tokens', async () => {
            await weth.approve(POOL, MAX);
            await mkr.approve(POOL, MAX);
            await dai.approve(POOL, MAX);
            await xxx.approve(POOL, MAX);
            await xxxWithFees.approve(POOL, MAX);
        });

        it('Fails binding token with fees', async () => {
            try {
                await pool.bindMMM(XXXWITHFEES, toWei('5'), toWei('1'), XXXOracleAddress);
                throw 'did not revert';
            }
            catch(e) {
                assert.equal(e.reason, 'SWAAP#52');
            }            
        });

        it('Fails binding weights and balances outside MIN MAX', async () => {
            try {
                await pool.bindMMM(WETH, toWei('51'), toWei('1'), WETHOracleAddress);
                throw 'did not revert';
            }
            catch(e) {
                assert.equal(e.reason, 'ERR_INSUFFICIENT_SP');
            }

            /*await truffleAssert.reverts(
                pool.bindMMM(WETH, toWei('51'), toWei('1'), WETHOracleAddress),
                'ERR_INSUFFICIENT_SP',
            );*/

            try {
                await pool.bindMMM(MKR, toWei('0.0000000000001'), toWei('1'), MKROracleAddress);
                throw 'did not revert';
            }
            catch(e) {
                assert.equal(e.reason, 'SWAAP#32');
            }
            /*await truffleAssert.reverts(
                pool.bindMMM(MKR, toWei('0.0000000000001'), toWei('1'), MKROracleAddress),
                '32',
            );*/
            
            try {
                await pool.bindMMM(DAI, toWei('1000'), toWei('0.99'), DAIOracleAddress);
                throw 'did not revert';
            }
            catch(e) {
                assert.equal(e.reason, 'SWAAP#30');
            }
            /*await truffleAssert.reverts(
                pool.bindMMM(DAI, toWei('1000'), toWei('0.99'), DAIOracleAddress),
                '30',
            );*/

            try {
                await pool.bindMMM(WETH, toWei('5'), toWei('50.01'), XXXOracleAddress);
                throw 'did not revert';
            }
            catch(e) {
                assert.equal(e.reason, 'SWAAP#31');
            }
            /*await truffleAssert.reverts(
                pool.bindMMM(WETH, toWei('5'), toWei('50.01'), XXXOracleAddress),
                '31',
            );*/
        });

        it('Fails finalizing pool without 2 tokens', async () => {
            await truffleAssert.reverts(
                pool.finalize(),
                'SWAAP#18',
            );
        });

        it('Fails binding when there is a new pending controller', async () => {
            await pool.transferOwnership(user1);
            
            try {
                await pool.bindMMM(WETH, (50*10**wethDecimals).toString(), toWei('5'), WETHOracleAddress);
                throw 'did not revert';
            }
            catch(e) {
                assert.equal(e.reason, 'SWAAP#51');
            }

            await pool.transferOwnership('0x0000000000000000000000000000000000000000');            
        }); 

        it('Admin binds tokens', async () => {
            // Equal weights WETH, MKR, DAI
            await pool.bindMMM(WETH, (50*10**wethDecimals).toString(), toWei('5'), WETHOracleAddress);
            await pool.bindMMM(MKR, (2000*10**mkdrDecimals).toString(), toWei('5'), MKROracleAddress);
            await pool.bindMMM(DAI, (100000*10**daiDecimals).toString(), toWei('5'), DAIOracleAddress);
            const tokens = await pool.getTokens();
            const numTokens = tokens.length
            assert.equal(3, numTokens);
            const weights = await Promise.all(tokens.map(t => pool.getDenormalizedWeight(t)));
            const totalDenormWeight = weights.reduce((acc, v) => acc + parseFloat(fromWei(v)), 0);
            assert.equal(15, totalDenormWeight);
            const wethDenormWeight = await pool.getDenormalizedWeight(WETH);
            assert.equal(5, fromWei(wethDenormWeight));
            assert.equal(0.333333333333333333, fromWei(wethDenormWeight) / totalDenormWeight);
            const mkrBalance = await pool.getBalance(MKR);
            const relDif = calcRelativeDiff(2000*mkrDecimalsDiffFactor, fromWei(mkrBalance));
            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('Fails transferring ownership when tokens are binded and pool not finalized', async () => {
            

            try {
                await pool.transferOwnership(user1);
                throw 'did not revert';
            }
            catch(e) {
                assert.equal(e.reason, 'SWAAP#50');
            }
        }); 

        it('Admin unbinds token', async () => {
            await pool.bindMMM(XXX, toWei('10'), toWei('5'), XXXOracleAddress);
            let adminBalance = await xxx.balanceOf(admin);
            assert.equal(0, fromWei(adminBalance));
            await pool.unbindMMM(XXX);
            adminBalance = await xxx.balanceOf(admin);
            assert.equal(10, fromWei(adminBalance));
            const tokens = await pool.getTokens();
            const numTokens = tokens.length
            assert.equal(3, numTokens);
            const weights = await Promise.all(tokens.map(t => pool.getDenormalizedWeight(t)));
            const totalDenormWeight = weights.reduce((acc, v) => acc + parseFloat(fromWei(v)), 0);
            assert.equal(15, totalDenormWeight);
        });

        it('Fails binding above MAX TOTAL WEIGHT', async () => {
            try {
                await pool.bindMMM(XXX, toWei('1'), toWei('40'), XXXOracleAddress);
                throw 'did not revert';
            }
            catch(e) {
                assert(e.reason, 'SWAAP#33');
            }
            /*await truffleAssert.reverts(
                pool.bindMMM(XXX, toWei('1'), toWei('40'), XXXOracleAddress),
                '33',
            );*/
        });

        it('Fails rebinding token or unbinding random token', async () => {
            await truffleAssert.reverts(
                pool.bindMMM(WETH, toWei('0'), toWei('1'), WETHOracleAddress),
                'SWAAP#28',
            );
            await truffleAssert.reverts(
                pool.rebindMMM(XXX, toWei('0'), toWei('1'), XXXOracleAddress),
                'SWAAP#02',
            );
            await truffleAssert.reverts(
                pool.unbindMMM(XXX),
                'SWAAP#02',
            );
        });

        it('Get current tokens', async () => {
            const currentTokens = await pool.getTokens();
            assert.sameMembers(currentTokens, [WETH, MKR, DAI]);
        });

    });


    describe('Finalizing pool', () => {
        it('Fails when other users interact before finalizing', async () => {
            await truffleAssert.reverts(
                pool.bindMMM(WETH, toWei('5'), toWei('5'), WETHOracleAddress, { from: user1 }),
                'SWAAP#28',
            );
            await truffleAssert.reverts(
                pool.rebindMMM(WETH, toWei('5'), toWei('5'), WETHOracleAddress, { from: user1 }),
                'SWAAP#03',
            );
            await truffleAssert.reverts(
                pool.joinPool(toWei('1'), [MAX, MAX], { from: user1 }),
                'SWAAP#01',
            );
            await truffleAssert.reverts(
                pool.exitPool(toWei('1'), [toWei('0'), toWei('0')], { from: user1 }),
                'SWAAP#01',
            );
            await truffleAssert.reverts(
                pool.unbindMMM(DAI, { from: user1 }),
                'SWAAP#03',
            );
        });

        it('Fails calling any swap before finalizing', async () => {
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(WETH, toWei('2.5'), DAI, toWei('475'), toWei('200')),
                'SWAAP#10',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(DAI, toWei('2.5'), WETH, toWei('475'), toWei('200')),
                'SWAAP#10',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(WETH, toWei('2.5'), DAI, toWei('475'), toWei('200')),
                'SWAAP#10',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(DAI, toWei('2.5'), WETH, toWei('475'), toWei('200')),
                'SWAAP#10',
            );
        });

        it('Fails calling any join exit swap before finalizing', async () => {
            await truffleAssert.reverts(
                pool.joinswapExternAmountInMMM(WETH, toWei('2.5'), toWei('0')),
                'SWAAP#01',
            );
            await truffleAssert.reverts(
                pool.exitswapPoolAmountInMMM(WETH, toWei('2.5'), toWei('0')),
                'SWAAP#01',
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
                'SWAAP#14',
            );
        });

        it('Fails setting high swap fees', async () => {
            await truffleAssert.reverts(
                pool.setSwapFee(toWei('0.11')),
                'SWAAP#15',
            );
        });

        it('Fails nonadmin sets fees or controller', async () => {
            await truffleAssert.reverts(
                pool.setSwapFee(toWei('0.0015'), { from: user1 }),
                'SWAAP#12',
            );
            await truffleAssert.reverts(
                pool.setControllerAndTransfer(user1, { from: user1 }),
                'SWAAP#03',
            );
        });

        it('Admin sets swap fees', async () => {
            await pool.setSwapFee(toWei('0.0015'));
            const swapFee = await pool.getSwapFee();
            assert.equal(0.0015, fromWei(swapFee));
        });

        it('Admin sets dynamic spread parameters', async () => {
        	await pool.setPriceStatisticsLookbackInRound(1); // spread is now 0
        });

        it('Fails nonadmin finalizes pool', async () => {
            await truffleAssert.reverts(
                pool.finalize({ from: user1 }),
                'SWAAP#03',
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
                'SWAAP#04',
            );
        });

        it('Cant setPublicSwap, setSwapFee when finalized', async () => {
            await truffleAssert.reverts(pool.setPublicSwap(false), '4');
            await truffleAssert.reverts(pool.setSwapFee(toWei('0.01')), '4');
        });

        it('Fails binding new token after finalized', async () => {
            try {
                await pool.bindMMM(XXX, toWei('10'), toWei('5'), XXXOracleAddress);
                throw 'did not revert';
            }
            catch(e) {
                assert(e.reason, 'SWAAP#04');
            }
            try {
                await pool.rebindMMM(DAI, toWei('10'), toWei('5'), DAIOracleAddress);
                throw 'did not revert';
            }
            catch(e) {
                assert(e.reason, 'SWAAP#04');
            }
        });

        it('Fails unbinding after finalized', async () => {
            await truffleAssert.reverts(
                pool.unbindMMM(WETH),
                'SWAAP#04',
            );
        });

        it('Get final tokens', async () => {
            const finalTokens = await pool.getTokens();
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
                'SWAAP#36'
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(WETH, toWei('2.5'), DAI, toWei('475'), toWei('200'), { from: user2 }),
                 'SWAAP#36'
            );               
        });

        it('Fail User1 join/joinswap when Factory is paused', async () => {
            await truffleAssert.reverts(pool.joinPool(toWei('5'), [MAX, MAX, MAX], { from: user1 }), 'SWAAP#36');
            await truffleAssert.reverts(pool.joinswapExternAmountInMMM.call(WETH, toWei('0.1'), toWei('0')), 'SWAAP#36');
        });

        it('Admin unpauses pool', async () => {
            await factory.setPause(false, {from: admin});
        })

        it('User1 joins pool', async () => {
            await pool.joinPool(toWei('5'), [MAX, MAX, MAX], { from: user1 });
            const daiBalance = await pool.getBalance(DAI);
            const relDif = calcRelativeDiff(105000*daiDecimalsDiffFactor, fromWei(daiBalance));
            assert.isAtMost(relDif.toNumber(), errorDelta);
            const userWethBalance = await weth.balanceOf(user1);
            assert.equal(22.5, fromWei(userWethBalance));
        });

        it('Join a pool using getJoinPool returns', async () => {           
            
            await weth.mint(admin, (5*10**wethDecimals).toString());
            await mkr.mint(admin, (5*10**mkdrDecimals).toString());
            await dai.mint(admin, (5000*10**daiDecimals).toString());

            let daiAmountIn = (5000*10**daiDecimals).toString();
            const returns = await pool.getJoinPool.call(DAI, daiAmountIn);
            const poolAmountOut = returns[0];
            const tokenAmountsIn = returns[1];
            const tokens = await pool.getTokens.call();
            
            let balancesBefore = [];
            for (let i = 0; i < tokens.length; i++) {
                let token = await TToken.at(tokens[i]);
                balancesBefore.push(await token.balanceOf.call(admin));
            }

            await pool.joinPool(poolAmountOut, tokenAmountsIn);

            for (let i = 0; i < tokens.length; i++) {
                let token = await TToken.at(tokens[i]);
                let balanceAfter = await token.balanceOf.call(admin);
                
                assert.equal(balancesBefore[i].sub(tokenAmountsIn[i]).toString(), balanceAfter.toString());
            }
            
            let daiIndex = tokens.indexOf(DAI);
            let calculatedDaiAmountIn = tokenAmountsIn[daiIndex];
            // Relative difference between user input in the getter function and the real token input in joinPool
            let relDif = web3.utils.toBN(daiAmountIn).sub(calculatedDaiAmountIn);
            assert.isAtMost(relDif.toNumber(), 0);
        });

        it('Exit a pool using getExitPool returns', async () => {
            let poolAmoutIn = toWei('5');
            let tokenAmountsOut = (await pool.getExitPool(poolAmoutIn)); 

            const tokens = await pool.getTokens.call();
            let balancesBefore = [];
            for (let i = 0; i < tokens.length; i++) {
                let token = await TToken.at(tokens[i]);
                balancesBefore.push(await token.balanceOf.call(admin));
            }

            await pool.exitPool(poolAmoutIn, tokenAmountsOut);
            
            for (let i = 0; i < tokens.length; i++) {
                let token = await TToken.at(tokens[i]);
                let balanceAfter = await token.balanceOf.call(admin);

                assert.equal((balanceAfter.sub(tokenAmountsOut[i])).toString(), balancesBefore[i].toString());
            }
                    
        });

        
        it('User1 fails to join or exit pool with wrong maxAmounts length', async () => {
            truffleAssert.reverts(pool.joinPool(toWei('5'), [MAX, MAX, MAX, MAX], { from: user1 }),
            'SWAAP#54'
            );
            truffleAssert.reverts(pool.exitPool(toWei('5'), [MAX, MAX], { from: user1 }),
            'SWAAP#54'
            );
        });     

        /*
          Current pool balances
          WETH - 52.5
          MKR - 21
          DAI - 10,500
          XXX - 0
        */

        it('Fails admin unbinding token after finalized and others joined', async () => {
            await truffleAssert.reverts(pool.unbindMMM(DAI), 'SWAAP#04');
        });

        it('getSpotPriceSansFee', async () => {
            const wethPriceSansFee = await pool.getSpotPriceSansFee(DAI, WETH);
            const wethPriceSansFeeCheck = (105000 * daiDecimalsDiffFactor / 5) / (52.5 / 5);
            const relDif = calcRelativeDiff(wethPriceSansFeeCheck, fromWei(wethPriceSansFee));
            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('Fail swapExactAmountInMMM unbound or over min max ratios', async () => {
            try {
                await pool.swapExactAmountInMMM(WETH, toWei('2.5'), XXX, toWei('100'), toWei((200 / daiDecimalsDiffFactor).toString()), { from: user2 });
                throw 'did not revert';
            }
            catch(e) {
                assert(e.reason, 'SWAAP#02');
            }
            /*await truffleAssert.reverts(
                pool.swapExactAmountInMMM(WETH, toWei('2.5'), XXX, toWei('100'), toWei((200 / daiDecimalsDiffFactor).toString()), { from: user2 }),
                '2',
            );*/
            try {
                await pool.swapExactAmountInMMM(WETH, toWei('26.5'), DAI, toWei('5000'), toWei((200 / daiDecimalsDiffFactor).toString()), { from: user2 });
                throw 'did not revert';
            }
            catch(e) {
                assert(e.reason, 'SWAAP#57');
            }
            /*await truffleAssert.reverts(
                pool.swapExactAmountInMMM(WETH, toWei('26.5'), DAI, toWei('5000'), toWei((200 / daiDecimalsDiffFactor).toString()), { from: user2 }),
                '57',
            );*/
        });

        it('swapExactAmountInMMM', async () => {
            // 0.025 WETH -> DAI
            const expected = calcOutGivenIn(52.5/daiDecimalsDiffFactor, 5, 105000, 5, 0.025/daiDecimalsDiffFactor, 0.0015);
            const txr = await pool.swapExactAmountInMMM(
                WETH,
                toWei('0.025'),
                DAI,
                (49*10**daiDecimals).toString(),
                toWei((0.00051 / daiDecimalsDiffFactor).toString()),
                { from: user2 },
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');

            const actual = parseFloat(log.args[4]) / 10**daiDecimals;
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
            const wethPriceSansFee = await pool.getSpotPriceSansFee(DAI, WETH);
            const wethPriceSansFeeCheck = (104950.098727 * daiDecimalsDiffFactor / 5) / (52.525 / 5);
            assert.approximately(Number(fromWei(wethPriceSansFee)), Number(wethPriceSansFeeCheck), errorDelta);

            const daiNormWeight = await pool.getDenormalizedWeight(DAI);
            const tokens = await pool.getTokens();
            const weights = await Promise.all(tokens.map(t => pool.getDenormalizedWeight(t)));
            const totalDenormWeight = weights.reduce((acc, v) => acc + parseFloat(fromWei(v)), 0);
            assert.equal(0.333333333333333333, fromWei(daiNormWeight) / parseFloat(totalDenormWeight));
        });

        it('swapExactAmountOut', async () => {
            // WETH -> 1 MKR
            const expected = calcInGivenOut(52.525, 5, 2100*mkrDecimalsDiffFactor, 5, 1*mkrDecimalsDiffFactor, 0.0015);
            const txr = await pool.swapExactAmountOutMMM(
                WETH,
                toWei('0.026'),
                MKR,
                (1.0*10**mkdrDecimals).toString(),
                toWei((0.027 / mkrDecimalsDiffFactor).toString()),
                { from: user2 },
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');

            const actual = parseFloat(log.args[3]) / 10**wethDecimals;
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
                'SWAAP#08',
            );

            await truffleAssert.reverts(
                pool.exitPool(toWei('10'), [toWei('10'), toWei('1000'), toWei('10000')]),
                'SWAAP#09',
            );

            try {
                await pool.joinswapExternAmountInMMM(DAI, (1000*10**daiDecimals).toString(), toWei('10'));
                throw 'did not revert';
            }
            catch(e) {
                assert.equal(e.reason, 'SWAAP#09');
            }

            /*await truffleAssert.reverts(
                pool.joinswapExternAmountInMMM(DAI, (1000*10**daiDecimals).toString(), toWei('10')),
                '9',
            );*/

            try {
                await pool.exitswapPoolAmountInMMM(DAI, (1*10**daiDecimals).toString(), toWei('10000'));
                throw 'did not revert';
            }
            catch(e) {
                assert.equal(e.reason, 'SWAAP#09');
            }

            /*await truffleAssert.reverts(
                pool.exitswapPoolAmountInMMM(DAI, (1*10**daiDecimals).toString(), toWei('10000')),
                '9',
            );*/

        });

        it('Fails calling any swap on unbound token', async () => {
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(XXX, toWei('2.5'), DAI, toWei('475'), toWei('200')),
                'SWAAP#02',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(DAI, toWei('2.5'), XXX, toWei('475'), toWei('200')),
                'SWAAP#02',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(XXX, toWei('2.5'), DAI, toWei('475'), toWei('200')),
                'SWAAP#02',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(DAI, toWei('2.5'), XXX, toWei('475'), toWei('200')),
                'SWAAP#02',
            );
            await truffleAssert.reverts(
                 pool.joinswapExternAmountInMMM(XXX, toWei('2.5'), toWei('0')),
                'SWAAP#02',
            );
            await truffleAssert.reverts(
                pool.exitswapPoolAmountInMMM(XXX, toWei('2.5'), toWei('0')),
                'SWAAP#02',
            );
        });

        it('Fails calling weights, balances, spot prices on unbound token', async () => {
            await truffleAssert.reverts(
                pool.getDenormalizedWeight(XXX),
                'SWAAP#02',
            );
            await truffleAssert.reverts(
                pool.getBalance(XXX),
                'SWAAP#02',
            );
            await truffleAssert.reverts(
                pool.getSpotPriceSansFee(DAI, XXX),
                'SWAAP#02',
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
