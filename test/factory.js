const Pool = artifacts.require('Pool');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');
const TConstantOracle = artifacts.require('TConstantOracle');
const truffleAssert = require('truffle-assertions');

const {
    advanceTimeAndBlock
} = require('../lib/time');


contract('Factory', async (accounts) => {

    const admin = accounts[0];
    const nonAdmin = accounts[1];
    const user2 = accounts[2];
    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const { hexToUtf8 } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    describe('Factory', () => {
        let factory;
        let pool;
        let POOL;
        let WETH;
        let DAI;
        let weth;
        let dai;
        let wethOracle;
        let daiOracle;

        before(async () => {
            factory = await Factory.deployed();
            weth = await TToken.new('Wrapped Ether', 'WETH', 18);
            dai = await TToken.new('Dai Stablecoin', 'DAI', 18);

            WETH = weth.address;
            DAI = dai.address;

            // admin balances
            await weth.mint(admin, toWei('5'));
            await dai.mint(admin, toWei('200'));

            // nonAdmin balances
            await weth.mint(nonAdmin, toWei('1'), { from: admin });
            await dai.mint(nonAdmin, toWei('50'), { from: admin });

            POOL = await factory.newPool.call(); // this works fine in clean room
            await factory.newPool();
            pool = await Pool.at(POOL);

            await weth.approve(POOL, MAX);
            await dai.approve(POOL, MAX);

            await weth.approve(POOL, MAX, { from: nonAdmin });
            await dai.approve(POOL, MAX, { from: nonAdmin });
        });

        it('isPool on non pool returns false', async () => {
            const isPool = await factory.isPool(admin);
            assert.isFalse(isPool);
        });

        it('isPool on pool returns true', async () => {
            const isPool = await factory.isPool(POOL);
            assert.isTrue(isPool);
        });

        it('fails nonAdmin calls collect', async () => {
            await truffleAssert.reverts(factory.collect(nonAdmin, { from: nonAdmin }), 'SWAAP#34');
        });

        it('admin collects fees', async () => {
			wethOracle = await TConstantOracle.new(40);
			daiOracle = await TConstantOracle.new(1);
            await pool.bindMMM(WETH, toWei('5'), toWei('5'), wethOracle.address);
            await pool.bindMMM(DAI, toWei('200'), toWei('5'), daiOracle.address);

            await pool.finalize();
			let adminBalance = await pool.balanceOf(admin);
			assert.equal(fromWei(adminBalance), '100');

            await pool.joinPool(toWei('10'), [MAX, MAX], { from: nonAdmin });

            await pool.exitPool(toWei('10'), [toWei('0'), toWei('0')], { from: nonAdmin });
            // Exit fee = 0 so this wont do anything
            await factory.collect(POOL);

            adminBalance = await pool.balanceOf(admin);
            assert.equal(fromWei(adminBalance), '100');
        });

        it('factory sets pool parameters', async () => {
            await factory.setPoolSwapFee(POOL, toWei('0.01'));
            await factory.setPoolDynamicCoverageFeesZ(POOL, toWei('0.2'));
            await factory.setPoolDynamicCoverageFeesHorizon(POOL, toWei('3'));
            await factory.setPoolPriceStatisticsLookbackInRound(POOL, '5');
            await factory.setPoolPriceStatisticsLookbackInSec(POOL, '6000');
            await factory.setPoolPriceStatisticsLookbackStepInRound(POOL, '3');
            await factory.setPoolMaxPriceUnpegRatio(POOL, toWei('1.03'));

            let swapFee = await pool.getSwapFee();
            let coverageParams = await pool.getCoverageParameters();

            assert.equal(swapFee, toWei('0.01'));
            assert.equal(coverageParams[0], toWei('0.2'));
            assert.equal(coverageParams[1], toWei('3'));
            assert.equal(coverageParams[2], '5');
            assert.equal(coverageParams[3], '6000');
            assert.equal(coverageParams[4], '3');
            assert.equal(coverageParams[5], toWei('1.03'));
        });

        it('nonadmin fails to set pool parameters', async () => {
            await truffleAssert.reverts(factory.setPoolSwapFee(POOL, toWei('0.01'), {from: user2}), 'SWAAP#34');
            await truffleAssert.reverts(factory.setPoolDynamicCoverageFeesZ(POOL, toWei('0.2'), {from: user2}), 'SWAAP#34');
            await truffleAssert.reverts(factory.setPoolDynamicCoverageFeesHorizon(POOL, toWei('3'), {from: user2}), 'SWAAP#34');
            await truffleAssert.reverts(factory.setPoolPriceStatisticsLookbackInRound(POOL, '5', {from: user2}), 'SWAAP#34');
            await truffleAssert.reverts(factory.setPoolPriceStatisticsLookbackInSec(POOL, '6000', {from: user2}), 'SWAAP#34');
            await truffleAssert.reverts(factory.setPoolPriceStatisticsLookbackStepInRound(POOL, '3', {from: user2}), 'SWAAP#34');
            await truffleAssert.reverts(factory.setPoolMaxPriceUnpegRatio(POOL, toWei('1.03'), {from: user2}), 'SWAAP#34');
        });

        it('admin fails to set pool parameters when control is revoked', async () => {
            await factory.revokePoolFactoryControl(POOL);
            await truffleAssert.reverts(factory.setPoolSwapFee(POOL, toWei('0.01')), 'SWAAP#07');
            await truffleAssert.reverts(factory.setPoolDynamicCoverageFeesZ(POOL, toWei('0.2')), 'SWAAP#07');
            await truffleAssert.reverts(factory.setPoolDynamicCoverageFeesHorizon(POOL, toWei('3')), 'SWAAP#07');
            await truffleAssert.reverts(factory.setPoolPriceStatisticsLookbackInRound(POOL, '5'), 'SWAAP#07');
            await truffleAssert.reverts(factory.setPoolPriceStatisticsLookbackInSec(POOL, '6000'), 'SWAAP#07');
            await truffleAssert.reverts(factory.setPoolPriceStatisticsLookbackStepInRound(POOL, '3'), 'SWAAP#07');
            await truffleAssert.reverts(factory.setPoolMaxPriceUnpegRatio(POOL, toWei('1.03')), 'SWAAP#07');
        });        

        it('nonadmin cant set swaaplabs address', async () => {
            await truffleAssert.reverts(factory.transferOwnership(nonAdmin, { from: nonAdmin }), 'SWAAP#34');
            await truffleAssert.reverts(factory.acceptOwnership({ from: nonAdmin }), 'SWAAP#20');
        });

        it('fails to create new pool when paused', async () => {
            await factory.setPause(true, {from: admin});
            await truffleAssert.reverts(factory.newPool.call(), 'SWAAP#36');
        });

        it('nonadmin cannot set/unset pause', async () => {
            await truffleAssert.reverts(factory.setPause(false, { from: nonAdmin }), 'SWAAP#34');
            await truffleAssert.reverts(factory.setPause(true, { from: nonAdmin }), 'SWAAP#34');
        });
        
        it('create pool after unpausing', async () => {
            await factory.setPause(false, {from: admin});
            await factory.newPool.call();
        });

        it('admin cannot set/unset pause after time window', async () => {
            await advanceTimeAndBlock(86400 * 61);
            await truffleAssert.reverts(factory.setPause(true, {from: admin}), 'SWAAP#45');
            await truffleAssert.reverts(factory.setPause(false, {from: admin}), 'SWAAP#45');
        });

        it('admin changes swaaplabs address', async () => {
            await factory.transferOwnership(user2, {from: admin});
            await factory.acceptOwnership({from: user2});
            const blab = await factory.getSwaapLabs();
            assert.equal(blab, user2);
        });

    });
});
