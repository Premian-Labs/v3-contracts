import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
    ERC20Mock, ERC20Mock__factory, IPoolMock__factory, UnderwriterVault__factory,
    UnderwriterVaultMock,
    UnderwriterVaultProxy,
    UnderwriterVaultMock__factory, UnderwriterVaultProxy__factory, IERC20__factory
} from "../../../typechain";
import { BigNumber } from 'ethers';
import {IERC20} from "../../../typechain";
import {SafeERC20} from "../../../typechain";


import { parseEther, parseUnits, formatEther} from 'ethers/lib/utils';
import {
    deployMockContract,
    MockContract,
} from '@ethereum-waffle/mock-contract';
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

describe('UnderwriterVault', () => {
    let deployer: SignerWithAddress;
    let lp: SignerWithAddress;

    let proxy: UnderwriterVaultProxy;
    let vault: UnderwriterVaultMock;

    let base: ERC20Mock;
    let quote: ERC20Mock;

    let baseOracle: MockContract;
    let volOracle: MockContract;

    const log = true;

    before(async () => {
        [deployer, lp] = await ethers.getSigners();

        base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
        quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

        await base.deployed();
        await quote.deployed();

        await base.mint(lp.address, parseEther('1000'));
        await quote.mint(lp.address, parseEther('1000000'));

        await base.mint(deployer.address, parseEther('1000'));
        await quote.mint(deployer.address, parseEther('1000000'));

        baseOracle = await deployMockContract(deployer as any, [
            'function latestAnswer() external view returns (int256)',
            'function decimals () external view returns (uint8)',
        ]);

        await baseOracle.mock.latestAnswer.returns(parseUnits('1', 8));
        await baseOracle.mock.decimals.returns(8);

        // todo: connect to volatility oracle
        volOracle = await deployMockContract(deployer as any, [
            'function latestAnswer() external view returns (int256)',
            'function decimals () external view returns (uint8)',
        ]);

        await volOracle.mock.latestAnswer.returns(parseUnits('1', 8));
        await volOracle.mock.decimals.returns(8);

        vault = await new UnderwriterVaultMock__factory(deployer).deploy(volOracle.address);
        await vault.deployed();

        vault = UnderwriterVaultMock__factory.connect(vault.address, deployer);
        await vault.deployed();

        if (log) console.log(`UnderwriterVault : ${vault.address}`);

        proxy = await new UnderwriterVaultProxy__factory(deployer).deploy(
            vault.address,
            base.address,
            quote.address,
            baseOracle.address,
            "WETH Vault",
            "WETH",
            true,
        );
        await proxy.deployed();

        if (log) console.log(`UnderwriterVaultProxy : ${proxy.address}`);

    });

    describe('#convertToShares', () => {
        it('if no shares have been minted, minted shares should equal deposited assets', async () => {
            const assetAmount = parseEther('2');
            const shareAmount = await vault.convertToShares(assetAmount);
            expect(shareAmount).to.eq(assetAmount);
        });
    });

    describe('#convertToAssets', () => {
        it('', async () => {
            const shareAmount = parseEther('2');
            const assetAmount = await vault.convertToAssets(shareAmount);
            expect(shareAmount).to.eq(assetAmount);
        });

    });

    describe('#maxDeposit', () => {
        it('', async () => {
            const assetAmount = await vault.maxDeposit(lp.address);
        });

    });

    describe('#previewDeposit', () => {
        it('', async () => {
            const assetAmount = parseEther('2');
            const sharesAmount = await vault.previewDeposit(assetAmount);
            console.log(formatEther(sharesAmount));
        });
    });

    describe('#maxMint', () => {
        it('', async () => {
            const test = await vault.maxMint(lp.address);
            console.log(formatEther(test));
        });
    });

    describe('#previewMint', () => {
        it('', async () => {
            const sharesAmount = parseEther('2');
            const test = await vault.previewMint(sharesAmount);
            console.log(formatEther(test));
        });
    });

    describe('#deposit', () => {
        const fnSig = 'deposit(uint256,address)';
        it('', async () => {
            const assetAmount = parseEther('2');
            let balance = await base.balanceOf(lp.address);
            console.log(formatEther(balance));
            let balancequote = await quote.balanceOf(lp.address);
            console.log(formatEther(balancequote));

            const allowedAmount = parseEther('4');

            await base.connect(lp).approve(vault.address, allowedAmount);
            console.log("0");
            await base.connect(lp).transfer(vault.address, assetAmount);
            console.log("0");

            console.log(base.address);
            console.log(vault.address);
            console.log(lp.address);

            // const shareAmount = await vault.deposit(assetAmount, vault.address);

            const shares = await vault.connect(lp).deposit(assetAmount, lp.address);
            //console.log(shareAmount);
            //expect(shareAmount).to.eq(assetAmount);
        });
    });

});