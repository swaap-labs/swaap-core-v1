const truffleAssert = require('truffle-assertions');

const TMath = artifacts.require('TMath');

contract('TMath', async () => {
    const MAX = web3.utils.toTwosComplement(-1);

    describe('Math', () => {
        let tmath;
        before(async () => {
            tmath = await TMath.deployed();
        });

        it('mul throws on overflow', async () => {
            await truffleAssert.reverts(tmath.calcMul(2, MAX), 'revert'); // ERR_MUL_OVERFLOW
        });

        it('div throws on div by 0', async () => {
            await truffleAssert.reverts(tmath.calcDiv(1, 0), 'revert');
        });

        it('pow throws on base outside range', async () => {
            await truffleAssert.reverts(tmath.calcPow(0, 2), 'SWAAP#39');
            await truffleAssert.reverts(tmath.calcPow(MAX, 2), 'SWAAP#40');
        });
    });
});
