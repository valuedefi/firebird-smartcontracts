import {expect} from '../chai-setup';
import {ethers} from 'hardhat';
import {Contract, ContractFactory, BigNumber, utils} from 'ethers';
import {Provider} from '@ethersproject/providers';
import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';

import {
    ADDRESS_ZERO, MAX_UINT256, fromWei, toWei,
    getLatestBlock,
    getLatestBlockNumber,
    getLatestBlockTime,
    mineBlocks, mineBlockTimeStamp, mineOneBlock, setNextBlockTimestamp
} from '../shared/utilities';

const ONE_WEEK_SECONDS = 7 * 24 * 3600;
const INITIAL_AMOUNT = utils.parseEther('1000');

const TX01 = '0xe8f9b445d4d2012878f4c410572d62cf781fc16a9111bb91e74a69501951bee1';
const TX02 = '0xc1e52d478a803b2f5930d6e525cd89dea6713fd8f38c06dfd6ffcb52f0140d15';
const TX03 = '0x898fae641c0c0dbf794677db973bb6c656f6530aa45365110cccc891ef27efe0';

describe('ValueToHopeLocker.test', () => {
    const {provider} = ethers;

    let operator: SignerWithAddress;
    let admin: SignerWithAddress;
    let bob: SignerWithAddress;
    let carol: SignerWithAddress;
    let david: SignerWithAddress;

    before('provider & accounts setting', async () => {
        // @ts-ignore
        [operator, admin, bob, carol, david] = await ethers.getSigners();
    });

    // core
    let HOPE: ContractFactory;
    let ValueToHopeLocker: ContractFactory;

    before('fetch contract factories', async () => {
        HOPE = await ethers.getContractFactory('HOPE');
        ValueToHopeLocker = await ethers.getContractFactory('ValueToHopeLocker');
    });

    let hope: Contract;
    let locker: Contract;

    let startReleaseTime: BigNumber;
    let endReleaseTime: BigNumber;

    before('deploy contracts', async () => {
        hope = await HOPE.connect(operator).deploy();
        await hope.connect(operator).initialize(toWei('500000000'));

        startReleaseTime = BigNumber.from(String(await getLatestBlockTime(ethers))).add(60);
        endReleaseTime = startReleaseTime.add(ONE_WEEK_SECONDS * 4);

        locker = await ValueToHopeLocker.connect(operator).deploy();
        await locker.connect(operator).initialize(hope.address, startReleaseTime, endReleaseTime);

        await hope.connect(operator).setExcludeFromFee(locker.address, true);
        await hope.connect(operator).setMinterCap(locker.address, toWei('500000000'));
        await locker.connect(operator).addAuthority(admin.address);
    });

    describe('#constructor', () => {
        it('should works correctly', async () => {
            expect(String(await locker.startReleaseTime())).to.eq(String(startReleaseTime));
            expect(String(await locker.endReleaseTime())).to.eq(String(endReleaseTime));
            expect(String(await locker.totalLock())).to.eq(toWei('0'));
            expect(String(await locker.totalReleased())).to.eq(toWei('0'));
        });
    });

    describe('#addAuthority', () => {
        it('should fail if addAuthority by non-owner', async () => {
            await expect(locker.connect(bob).addAuthority(carol.address)).to.be.revertedWith('Ownable: caller is not the owner');
        });

        it('bob is added as authority', async () => {
            expect(await locker.authorities(bob.address)).to.be.false;
            await locker.connect(operator).addAuthority(bob.address);
            expect(await locker.authorities(bob.address)).to.be.true;
        });
    });

    describe('#removeAuthority', () => {
        it('should fail if removeAuthority by non-owner', async () => {
            await expect(locker.connect(bob).removeAuthority(carol.address)).to.be.revertedWith('Ownable: caller is not the owner');
        });

        it('bob is removed as authority', async () => {
            expect(await locker.authorities(bob.address)).to.be.true;
            await locker.connect(operator).removeAuthority(bob.address);
            expect(await locker.authorities(bob.address)).to.be.false;
        });
    });

    describe('#lock', () => {
        it('should fail if bob is not authorised to lock', async () => {
            await expect(locker.connect(bob).lock(bob.address, toWei('10'), TX01)).to.be.revertedWith('!authorised');
        });

        it('bob lock 10 HOPE', async () => {
            await expect(async () => {
                await locker.connect(admin).lock(bob.address, toWei('10'), TX01);
            }).to.changeTokenBalances(hope, [bob, locker], [toWei('0'), toWei('0')]);
            expect(String(await locker.lockOf(bob.address))).to.eq(toWei('10'));
            expect(String(await locker.released(bob.address))).to.eq(toWei('0'));
        });

        it('should fail if bob lock again with same txhash', async () => {
            await expect(locker.connect(admin).lock(bob.address, toWei('10'), TX01)).to.be.revertedWith('already locked');
        });
    });

    describe('#unlock', () => {
        it('should fail before released time', async () => {
            console.log('_startReleaseTime = %s', String(await locker.startReleaseTime()));
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            await expect(locker.connect(bob).unlock()).to.be.revertedWith('still locked');
        });

        it('bob unlock after 1 hour', async () => {
            const latestBlockTime = await getLatestBlockTime(ethers);
            await setNextBlockTimestamp(ethers, latestBlockTime + 3600);
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            await expect(async () => {
                await locker.connect(bob).unlock();
            }).to.changeTokenBalances(hope, [bob, locker], [toWei('0.01468667328042328'), toWei('0')]);
            expect(String(await locker.lockOf(bob.address))).to.eq(toWei('10'));
            expect(String(await locker.released(bob.address))).to.eq(toWei('0.01468667328042328'));
            expect(String(await locker.totalLock())).to.eq(toWei('9.98531332671957672'));
            expect(String(await locker.totalReleased())).to.eq(toWei('0.01468667328042328'));
        });

        it('bob lock 10 HOPE and unlock again after 1 day', async () => {
            await locker.connect(admin).lock(bob.address, toWei('10'), TX02);
            const latestBlockTime = await getLatestBlockTime(ethers);
            await setNextBlockTimestamp(ethers, latestBlockTime + 24 * 3600);
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            await expect(async () => {
                await locker.connect(bob).unlock();
            }).to.changeTokenBalances(hope, [bob, locker], [toWei('0.728980654761904762'), toWei('0')]);
            expect(String(await locker.lockOf(bob.address))).to.eq(toWei('20'));
            expect(String(await locker.released(bob.address))).to.eq(toWei('0.743667328042328042'));
            expect(String(await locker.totalLock())).to.eq(toWei('19.256332671957671958'));
            expect(String(await locker.totalReleased())).to.eq(toWei('0.743667328042328042'));
        });

        it('bob unlock after end of released', async () => {
            await setNextBlockTimestamp(ethers, endReleaseTime.toNumber());
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            await expect(async () => {
                await locker.connect(bob).unlock();
            }).to.changeTokenBalances(hope, [bob, locker], [toWei('19.256332671957671958'), toWei('0')]);
            expect(String(await locker.lockOf(bob.address))).to.eq(toWei('20'));
            expect(String(await locker.released(bob.address))).to.eq(toWei('20'));
            expect(String(await locker.totalLock())).to.eq(toWei('0'));
            expect(String(await locker.totalReleased())).to.eq(toWei('20'));
        });

        it('carol lock after end of released', async () => {
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            await expect(async () => {
                await locker.connect(admin).lock(carol.address, toWei('100'), TX03);
                await locker.connect(bob).claimUnlockedFor(carol.address);
            }).to.changeTokenBalances(hope, [bob, carol, locker], [toWei('0'), toWei('100'), toWei('0')]);
            expect(String(await locker.lockOf(carol.address))).to.eq(toWei('100'));
            expect(String(await locker.released(carol.address))).to.eq(toWei('100'));
            expect(String(await locker.totalLock())).to.eq(toWei('0'));
            expect(String(await locker.totalReleased())).to.eq(toWei('120'));
        });

        it('should fail if unlock with zero balance', async () => {
            await expect(locker.connect(carol).unlock()).to.be.revertedWith('ValueToHopeLocker: no locked');
        });
    });
});
