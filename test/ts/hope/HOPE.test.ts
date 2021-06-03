import {expect} from '../chai-setup';
import {ethers} from 'hardhat';
import {Contract, ContractFactory, BigNumber, utils} from 'ethers';
import {Provider} from '@ethersproject/providers';
import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';

import {
    ADDRESS_ZERO, MAX_UINT256, fromWei, toWei,
    getLatestBlock,
    getLatestBlockNumber,
    mineBlocks, mineBlockTimeStamp, mineOneBlock
} from '../shared/utilities';

describe('HOPE.test', () => {
    const {provider} = ethers;

    let operator: SignerWithAddress;
    let bob: SignerWithAddress;
    let carol: SignerWithAddress;
    let david: SignerWithAddress;

    before('provider & accounts setting', async () => {
        [operator, bob, carol, david] = await ethers.getSigners();
    });

    // core
    let HOPE: ContractFactory;

    before('fetch contract factories', async () => {
        HOPE = await ethers.getContractFactory('HOPE');
    });

    let token: Contract;

    before('deploy contracts', async () => {
        token = await HOPE.connect(operator).deploy();
        await token.connect(operator).initialize(toWei('500000000'));
        await token.connect(operator).setMinterCap(operator.address, toWei('500000000'));
    });

    describe('#constructor', () => {
        it('should works correctly', async () => {
            expect(String(await token.name())).to.eq('Firebird.Finance');
            expect(String(await token.symbol())).to.eq('HOPE');
            expect(String(await token.cap())).to.eq(toWei('500000000'));
            expect(String(await token.balanceOf(operator.address))).to.eq(toWei('10')); // pre-mint 10 HOPE
            expect(String(await token.totalSupply())).to.eq(toWei('10'));
            expect(String(await token.burnRate())).to.eq('0');
        });

        it('should fail if initialize twice', async () => {
            await expect(token.connect(operator).initialize(toWei('1000000'))).to.revertedWith('Contract instance has already been initialized');
        });
    });

    describe('#setMinterCap', () => {
        it('add minter cap for carol', async () => {
            await token.connect(operator).setMinterCap(carol.address, toWei('1000'));
            expect(await token.minterCap(carol.address)).to.eq(toWei('1000'));
        });

        it('carol mint 10 HOPE for david', async () => {
            await expect(async () => {
                await token.connect(carol).mint(carol.address, toWei('10'));
                await token.connect(carol).mint(david.address, toWei('20'));
            }).to.changeTokenBalances(token, [carol, david], [toWei('10'), toWei('20')]);
            expect(String(await token.totalSupply())).to.eq(toWei('40'));
            expect(String(await token.minterCap(carol.address))).to.eq(toWei('970'));
        });

        it('should fail if carol mint more than her minter cap', async () => {
            await expect(token.connect(carol).mint(carol.address, toWei('999999'))).to.revertedWith('HOPE: minting amount exceeds minter cap');
        });

        it('remove minter of carol', async () => {
            await token.connect(operator).setMinterCap(carol.address, 0);
            expect(await token.minterCap(carol.address)).to.eq(toWei('0'));
        });

        it('should fail if carol mint more', async () => {
            await expect(token.connect(carol).mint(carol.address, toWei('10'))).to.revertedWith('!minter');
        });

        it('should fail if add minter for carol by non-privilege account', async () => {
            await expect(token.connect(bob).mint(carol.address, toWei('10'))).to.revertedWith('!minter');
        });
    });

    describe('#transfer', () => {
        it('transfer: burn fee', async () => {
            await token.connect(operator).setBurnRate(50); // 0.05%
            await token.connect(operator).mint(bob.address, toWei('100000'));
            await expect(async () => {
                await token.connect(bob).transfer(carol.address, toWei('10000'));
            }).to.changeTokenBalances(token, [bob, carol], [toWei('-10000'), toWei('9950')]);
            expect(String(await token.totalBurned())).to.eq(toWei('50'));
            expect(String(await token.totalSupply())).to.eq(toWei('99990'));
        });
    });

    describe('#transfer from excluded account', () => {
        it('transfer from usual to usual account', async () => {
            await expect(async () => {
                await token.connect(bob).transfer(carol.address, toWei('10000'));
            }).to.changeTokenBalances(token, [bob, carol], [toWei('-10000'), toWei('9950')]);
        });

        it('transfer from excluded to usual account', async () => {
            await token.connect(operator).setExcludeFromFee(bob.address, true);
            await expect(async () => {
                await token.connect(bob).transfer(carol.address, toWei('10000'));
            }).to.changeTokenBalances(token, [bob, carol], [toWei('-10000'), toWei('10000')]);
        });

        it('transfer from usual to excluded account', async () => {
            await token.connect(operator).setExcludeFromFee(bob.address, false);
            await token.connect(operator).setExcludeToFee(carol.address, true);
            await expect(async () => {
                await token.connect(bob).transfer(carol.address, toWei('10000'));
            }).to.changeTokenBalances(token, [bob, carol], [toWei('-10000'), toWei('10000')]);
        });
    });
});
