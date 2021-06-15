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

const ONE_DAY_SECONDS = 24 * 3600;
const INITIAL_AMOUNT = utils.parseEther('1000');

describe('VotingEscrowToken.test', () => {
    const {provider} = ethers;

    let operator: SignerWithAddress;
    let admin: SignerWithAddress;
    let bob: SignerWithAddress;
    let carol: SignerWithAddress;
    let david: SignerWithAddress;

    before('provider & accounts setting', async () => {
        [operator, admin, bob, carol, david] = await ethers.getSigners();
    });

    // core
    let TToken: ContractFactory;
    let VotingEscrowToken: ContractFactory;

    before('fetch contract factories', async () => {
        TToken = await ethers.getContractFactory('TToken');
        VotingEscrowToken = await ethers.getContractFactory('VotingEscrowToken');
    });

    let lockedToken: Contract;
    let votingToken: Contract;

    let startReleaseTime: BigNumber;
    let endReleaseTime: BigNumber;

    before('deploy contracts', async () => {
        lockedToken = await TToken.connect(operator).deploy('TToken', 'TToken', 18);

        votingToken = await VotingEscrowToken.connect(operator).deploy();
        await votingToken.connect(operator).initialize('mHOPE', 'mHOPE', lockedToken.address, toWei('10'));

        await lockedToken.connect(operator).mint(bob.address, INITIAL_AMOUNT);
        await lockedToken.connect(operator).mint(carol.address, INITIAL_AMOUNT);
    });

    describe('#constructor', () => {
        it('should works correctly', async () => {
            expect(String(await votingToken.lockedToken())).to.eq(String(lockedToken.address));
            expect(String(await votingToken.minLockedAmount())).to.eq(toWei('10'));
            expect(String(await votingToken.earlyWithdrawFeeRate())).to.eq('5000');
        });

        it('should fail if initialize twice', async () => {
            await expect(votingToken.connect(operator).initialize('mHOPE', 'mHOPE', lockedToken.address, toWei('10'))).to.revertedWith('Contract instance has already been initialized');
        });
    });

    describe('#create_lock', () => {
        it('should fail if create_lock more than balance', async () => {
            await expect(votingToken.connect(bob).create_lock(toWei('2000'), 7)).to.be.revertedWith('SafeERC20: low-level call failed');
        });

        it('should fail if create_lock for only 1 day', async () => {
            await expect(votingToken.connect(bob).create_lock(toWei('10'), 1)).to.be.revertedWith('Voting lock can be 7 days min');
        });

        it('should fail if create_lock for too long (5 years)', async () => {
            await expect(votingToken.connect(bob).create_lock(toWei('10'), 5 * 360)).to.be.revertedWith('Voting lock can be 4 years max');
        });

        it('should fail if create_lock before approve', async () => {
            await expect(votingToken.connect(bob).create_lock(toWei('10'), 7)).to.be.revertedWith('SafeERC20: low-level call failed');
        });

        it('bob create_lock 10 TOKEN', async () => {
            await lockedToken.connect(bob).approve(votingToken.address, MAX_UINT256);
            await expect(async () => {
                await votingToken.connect(bob).create_lock(toWei('10'), 7);
            }).to.changeTokenBalances(lockedToken, [bob, votingToken], [toWei('-10'), toWei('10')]);
            expect(String(await votingToken.balanceOf(bob.address))).to.eq(toWei('0.048611111111111111'));
            expect(String(await votingToken.totalSupply())).to.eq(toWei('0.048611111111111111'));
        });

        it('should fail if create_lock when old lock exists', async () => {
            await expect(votingToken.connect(bob).create_lock(toWei('10'), 7)).to.be.revertedWith('Withdraw old tokens first');
        });
    });

    describe('#deposit_for', () => {
        it('carol deposit_for bob 10 TOKEN', async () => {
            await lockedToken.connect(carol).approve(votingToken.address, MAX_UINT256);
            await expect(async () => {
                await votingToken.connect(carol).deposit_for(bob.address, toWei('10'));
            }).to.changeTokenBalances(lockedToken, [bob, carol, votingToken], [toWei('0'), toWei('-10'), toWei('10')]);
            expect(String(await votingToken.locked__of(bob.address))).to.eq(toWei('20'));
            expect(String(await votingToken.balanceOf(carol.address))).to.eq(toWei('0'));
            expect(String(await votingToken.balanceOf(bob.address))).to.eq(toWei('0.097221981095679012'));
            expect(String(await votingToken.totalSupply())).to.eq(toWei('0.097221981095679012'));
        });
    });

    describe('#increase_amount', () => {
        it('bob increase_amount 10 TOKEN', async () => {
            const latestBlockTime = await getLatestBlockTime(ethers);
            await setNextBlockTimestamp(ethers, latestBlockTime + 6 * ONE_DAY_SECONDS); // move to next 6 day (almost unlocked
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            await expect(async () => {
                await votingToken.connect(bob).increase_amount(toWei('10'));
            }).to.changeTokenBalances(lockedToken, [bob, votingToken], [toWei('-10'), toWei('10')]);
            expect(String(await votingToken.locked__of(bob.address))).to.eq(toWei('30'));
            expect(String(await votingToken.balanceOf(bob.address))).to.eq(toWei('0.104166184413580246'));
            expect(String(await votingToken.totalSupply())).to.eq(toWei('0.104166184413580246'));
        });
    });

    describe('#increase_unlock_time', () => {
        it('bob increase_unlock_time 1 month', async () => {
            console.log('bob end locked = %s', String(await votingToken.locked__end(bob.address)));
            await expect(async () => {
                await votingToken.connect(bob).increase_unlock_time(30);
            }).to.changeTokenBalances(lockedToken, [bob, votingToken], [toWei('0'), toWei('0')]);
            console.log('bob end locked = %s', String(await votingToken.locked__end(bob.address)));
            expect(String(await votingToken.balanceOf(bob.address))).to.eq(toWei('0.729166184413580246'));
            expect(String(await votingToken.totalSupply())).to.eq(toWei('0.729166184413580246'));
        });
    });

    describe('#withdraw', () => {
        it('should fail if withdraw before lock expire', async () => {
            await expect(votingToken.connect(bob).withdraw()).to.be.revertedWith('The lock didn\'t expire');
        });

        it('bob withdraw 30 TOKEN', async () => {
            const latestBlockTime = await getLatestBlockTime(ethers);
            await setNextBlockTimestamp(ethers, latestBlockTime + 31 * ONE_DAY_SECONDS); // move to next month
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            await lockedToken.connect(bob).approve(votingToken.address, MAX_UINT256);
            await expect(async () => {
                await votingToken.connect(bob).withdraw();
            }).to.changeTokenBalances(lockedToken, [bob, votingToken], [toWei('30'), toWei('-30')]);
            expect(String(await votingToken.locked__of(bob.address))).to.eq(toWei('0'));
            expect(String(await votingToken.balanceOf(bob.address))).to.eq(toWei('0.729166184413580246'));
            expect(String(await votingToken.totalSupply())).to.eq(toWei('0.729166184413580246'));
        });

        it('should fail if withdraw again', async () => {
            await expect(votingToken.connect(bob).withdraw()).to.be.revertedWith('Nothing to withdraw');
        });
    });

    describe('#create_lock MAX 4 years', () => {
        it('bob create_lock 100 TOKEN for MAX 4 years', async () => {
            await expect(async () => {
                await votingToken.connect(bob).create_lock(toWei('100'), 4 * 360);
            }).to.changeTokenBalances(votingToken, [bob], [toWei('100')]);
        });
    });

    describe('#emergencyWithdraw', () => {
        it('bob emergencyWithdraw 100 TOKEN and get penalty of 50%', async () => {
            await expect(async () => {
                await votingToken.connect(bob).emergencyWithdraw();
            }).to.changeTokenBalances(lockedToken, [bob, votingToken], [toWei('50'), toWei('-100')]);
            expect(String(await lockedToken.balanceOf(votingToken.address))).to.eq(toWei('0'));
        });
    });
});
