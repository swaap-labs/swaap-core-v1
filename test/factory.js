const Pool = artifacts.require('Pool');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');
const TConstantOracle = artifacts.require('TConstantOracle');
const truffleAssert = require('truffle-assertions');
const {
    advanceBlock,
    advanceTimeAndBlock
} = require('../lib/time');


contract('Factory', async (accounts) => {

	let now = 1641893000;

    const admin = accounts[0];
    const nonAdmin = accounts[1];
    const user2 = accounts[2];
    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const { hexToUtf8 } = web3.utils;

    const increaseTime = function(duration) {
        const id = Date.now()
      
        return new Promise((resolve, reject) => {
          web3.currentProvider.sendAsync({
            jsonrpc: '2.0',
            method: 'evm_increaseTime',
            params: [duration],
            id: id,
          }, err1 => {
            if (err1) return reject(err1)
      
            web3.currentProvider.sendAsync({
              jsonrpc: '2.0',
              method: 'evm_mine',
              id: id+1,
            }, (err2, res) => {
              return err2 ? reject(err2) : resolve(res)
            })
          })
        })
      }      

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
            await truffleAssert.reverts(factory.collect(nonAdmin, { from: nonAdmin }), '34');
        });

        it('admin collects fees', async () => {
			wethOracle = await TConstantOracle.new(40, now);
			daiOracle = await TConstantOracle.new(1, now);
            await pool.bindMMM(WETH, toWei('5'), toWei('5'), wethOracle.address);
            await pool.bindMMM(DAI, toWei('200'), toWei('5'), daiOracle.address);

            await pool.finalize();
			let adminBalance = await pool.balanceOf(admin);
			assert.equal(fromWei(adminBalance), '100');

            await pool.joinPool(toWei('10'), [MAX, MAX], { from: nonAdmin });
            // By default with truffle each transaction is mined on a different block so we only need to skip 2 block for JIT
            await advanceBlock(2);
            await pool.exitPool(toWei('10'), [toWei('0'), toWei('0')], { from: nonAdmin });
            // Exit fee = 0 so this wont do anything
            await factory.collect(POOL);

            adminBalance = await pool.balanceOf(admin);
            assert.equal(fromWei(adminBalance), '100');
        });

        it('nonadmin cant set swaaplabs address', async () => {
            await truffleAssert.reverts(factory.setSwaapLabs(nonAdmin, { from: nonAdmin }), '34');
        });

        it('fails to create new pool when paused', async () => {
            await factory.setPause(true, {from: admin});
            await truffleAssert.reverts(factory.newPool.call(), '36');
        });

        it('nonadmin cannot set/unset pause', async () => {
            await truffleAssert.reverts(factory.setPause(false, { from: nonAdmin }), '34');
            await truffleAssert.reverts(factory.setPause(true, { from: nonAdmin }), '34');
        });
        
        it('create pool after unpausing', async () => {
            await factory.setPause(false, {from: admin});
            await factory.newPool.call();
        });

        it('admin cannot set/unset pause after time window', async () => {
            await advanceTimeAndBlock(86400 * 61);
            await truffleAssert.reverts(factory.setPause(true, {from: admin}), '45');
            await truffleAssert.reverts(factory.setPause(false, {from: admin}), '45');
        });

        it('admin changes swaaplabs address', async () => {
            await factory.setSwaapLabs(user2);
            const blab = await factory.getSwaapLabs();
            assert.equal(blab, user2);
        });

    });
});
