const TErr = artifacts.require('TErr');
const truffleAssert = require('truffle-assertions');

contract('Errors Library', async (accounts) => {

    let terr;

    describe('Errors Library', () => {

        before(async () => {
            terr = await TErr.deployed();    
        });

        it('Does not revert when condition is true', async () => {
            await terr._requireTest(true, 44);
        });
        
        it('Reverts with message "SWAAP#00"', async() => {
            await truffleAssert.reverts(terr._requireTest(false, 0), 'SWAAP#00');
        });

        it('Reverts with message "SWAAP#01"', async() => {
            await truffleAssert.reverts(terr._requireTest(false, 1), 'SWAAP#01');
        });

        it('Reverts with message "SWAAP#20"', async() => {
            await truffleAssert.reverts(terr._requireTest(false, 20), 'SWAAP#20');
        });

        it('Reverts with message "SWAAP#44"', async() => {
            await truffleAssert.reverts(terr._requireTest(false, 44), 'SWAAP#44');
        });

    });
});
