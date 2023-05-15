import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { addDeposit, callVault, vaultSetup } from '../UnderwriterVault.fixture';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { formatEther, parseEther, parseUnits } from 'ethers/lib/utils';
import { setMaturities } from '../UnderwriterVault.fixture';
import { ERC20Mock, UnderwriterVaultMock } from '../../../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

describe('#ERC4626 overridden functions', () => {
  for (const isCall of [true, false]) {
    describe(isCall ? 'call' : 'put', () => {
      describe('#_totalAssets', () => {
        let vault: UnderwriterVaultMock;
        let token: ERC20Mock;
        const tests = [
          { totalAssets: 1 },
          {
            totalAssets: 1.1,
          },
          {
            totalAssets: 590.7,
          },
        ];

        tests.forEach(async (test) => {
          it(`totalAssets equals ${test.totalAssets}`, async () => {
            let { callVault, putVault, base, quote } = await loadFixture(
              vaultSetup,
            );
            vault = isCall ? callVault : putVault;
            token = isCall ? base : quote;

            await vault.setTotalAssets(parseEther(test.totalAssets.toString()));

            const expectedAmount = parseUnits(
              test.totalAssets.toString(),
              await token.decimals(),
            );
            expect(await vault.totalAssets()).to.eq(expectedAmount);
          });
        });
      });

      describe('#_previewWithdraw', () => {
        let vault: UnderwriterVaultMock;
        let token: ERC20Mock;

        const tests = [
          { totalSupply: 0, totalAssets: 0, assetAmount: 1, shareAmount: 1 },
          { totalSupply: 1, totalAssets: 0, assetAmount: 1, shareAmount: 1 },
          { totalSupply: 1, totalAssets: 1, assetAmount: 1, shareAmount: 1 },
          { totalSupply: 4, totalAssets: 1, assetAmount: 1, shareAmount: 4 },
          { totalSupply: 4, totalAssets: 5, assetAmount: 3, shareAmount: 2.4 },
        ];

        tests.forEach(async (test) => {
          async function setup() {
            let { callVault, putVault, base, quote } = await loadFixture(
              vaultSetup,
            );
            vault = isCall ? callVault : putVault;
            token = isCall ? base : quote;
            const decimals = await token.decimals();
            const balance = parseUnits(test.totalAssets.toString(), decimals);
            await token.mint(vault.address, balance);
            await vault.increaseTotalAssets(
              parseEther(test.totalAssets.toString()),
            );
            await vault.increaseTotalShares(
              parseEther(test.totalSupply.toString()),
            );
            return { vault, token };
          }

          it(`previewWithdraw returns ${test.shareAmount}`, async () => {
            let { vault, token } = await loadFixture(setup);
            const assetAmount = parseUnits(
              test.assetAmount.toString(),
              await token.decimals(),
            );

            if (test.totalSupply == 0) {
              await expect(
                vault.previewWithdraw(assetAmount),
              ).to.be.revertedWithCustomError(vault, 'Vault__ZeroShares');
            } else if (test.totalAssets == 0) {
              await expect(
                vault.previewWithdraw(assetAmount),
              ).to.be.revertedWithCustomError(
                vault,
                'Vault__InsufficientFunds',
              );
            } else {
              expect(await vault.previewWithdraw(assetAmount)).to.eq(
                parseEther(test.shareAmount.toString()),
              );
            }
          });
        });
      });

      describe('#maxWithdraw', () => {
        it('maxWithdraw should revert for a zero address', async () => {
          const { callVault, base, quote, lp } = await loadFixture(vaultSetup);
          await setMaturities(callVault);
          await addDeposit(callVault, lp, 2, base, quote);
          await expect(
            callVault.maxWithdraw(ethers.constants.AddressZero),
          ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
        });

        it('maxWithdraw should return the available assets for a non-zero address', async () => {
          const { callVault, receiver, base, quote } = await loadFixture(
            vaultSetup,
          );
          await setMaturities(callVault);
          await addDeposit(callVault, receiver, 3, base, quote);

          await callVault.increaseTotalLockedSpread(parseEther('0.1'));
          await callVault.increaseTotalLockedAssets(parseEther('0.5'));

          const assetAmount = await callVault.maxWithdraw(receiver.address);

          expect(assetAmount).to.eq(parseEther('2.4'));
        });

        it('maxWithdraw should return the assets the receiver owns', async () => {
          const { callVault, caller, receiver, base, quote } =
            await loadFixture(vaultSetup);
          await setMaturities(callVault);
          await addDeposit(callVault, caller, 8, base, quote);
          await addDeposit(callVault, receiver, 2, base, quote);
          await callVault.increaseTotalLockedSpread(parseEther('0.0'));
          await callVault.increaseTotalLockedAssets(parseEther('0.5'));
          const assetAmount = await callVault.maxWithdraw(receiver.address);
          expect(assetAmount).to.eq(parseEther('2'));
        });

        it('maxWithdraw should return the assets the receiver owns since there are sufficient funds', async () => {
          const { callVault, caller, receiver, base, quote } =
            await loadFixture(vaultSetup);
          await setMaturities(callVault);
          await addDeposit(callVault, caller, 7, base, quote);
          await addDeposit(callVault, receiver, 2, base, quote);
          await callVault.increaseTotalLockedSpread(parseEther('0.1'));
          await callVault.increaseTotalLockedAssets(parseEther('0.5'));
          const assetAmount = parseFloat(
            formatEther(await callVault.maxWithdraw(receiver.address)),
          );
          expect(assetAmount).to.be.closeTo(1.977777777777777, 0.00000001);
        });
      });

      describe('#maxRedeem', () => {
        it('maxRedeem should revert for a zero address', async () => {
          const { callVault, receiver, base, quote } = await loadFixture(
            vaultSetup,
          );
          await setMaturities(callVault);
          await addDeposit(callVault, receiver, 2, base, quote);
          await expect(
            callVault.maxRedeem(ethers.constants.AddressZero),
          ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
        });

        it('maxRedeem should return the amount of shares that are redeemable', async () => {
          const { callVault, receiver, base, quote } = await loadFixture(
            vaultSetup,
          );
          await setMaturities(callVault);
          await addDeposit(callVault, receiver, 3, base, quote);
          await callVault.increaseTotalLockedSpread(parseEther('0.1'));
          await callVault.increaseTotalLockedAssets(parseEther('0.5'));
          const assetAmount = await callVault.maxRedeem(receiver.address);
          expect(assetAmount).to.eq('2482758620689655174');
        });
      });

      describe('#previewMint', () => {
        it('previewMint should return amount of assets required to mint the amount of shares', async () => {
          const { callVault } = await loadFixture(vaultSetup);
          await setMaturities(callVault);
          const assetAmount = await callVault.previewMint(parseEther('2.1'));
          expect(assetAmount).to.eq(parseEther('2.1'));
        });

        it('previewMint should return amount of assets required to mint', async () => {
          const { callVault, receiver, base, quote } = await loadFixture(
            vaultSetup,
          );
          await setMaturities(callVault);
          await addDeposit(callVault, receiver, 2, base, quote);

          await callVault.increaseTotalLockedSpread(parseEther('0.2'));
          const assetAmount = await callVault.previewMint(parseEther('4'));
          expect(assetAmount).to.eq(parseEther('3.6'));
        });
      });

      describe('#convertToShares', () => {
        let vault: UnderwriterVaultMock;
        let token: ERC20Mock;
        let baseT: ERC20Mock;
        let quoteT: ERC20Mock;
        let receiver: SignerWithAddress;

        beforeEach(async () => {
          const { callVault, putVault, base, quote, lp } = await loadFixture(
            vaultSetup,
          );
          vault = isCall ? callVault : putVault;
          token = isCall ? base : quote;
          baseT = base;
          quoteT = quote;
          receiver = lp;
        });

        it('if no shares have been minted, minted shares should equal deposited assets', async () => {
          const assetAmount = parseUnits('2', await token.decimals());
          const shareAmount = await vault.convertToShares(assetAmount);
          const shareAmountExpected = parseEther('2');
          expect(shareAmount).to.eq(shareAmountExpected);
        });

        it('if supply is non-zero and pricePerShare is one, minted shares equals the deposited assets', async () => {
          await setMaturities(vault);
          await addDeposit(vault, receiver, 8, baseT, quoteT);
          const assetAmount = parseUnits('2', await token.decimals());
          const shareAmount = await vault.convertToShares(assetAmount);
          // share amount is always in 18 dp
          const shareAmountExpected = parseEther('2');
          expect(shareAmount).to.eq(shareAmountExpected);
        });

        it('if supply is non-zero, minted shares equals the deposited assets adjusted by the pricePerShare', async () => {
          const assetAmount = 2;
          await setMaturities(vault);
          await addDeposit(vault, receiver, 2, baseT, quoteT);

          await vault.increaseTotalLockedSpread(parseEther('1.0'));

          const assetAmountParsed = parseUnits(
            assetAmount.toString(),
            await token.decimals(),
          );
          const shareAmount = await vault.convertToShares(assetAmountParsed);
          expect(shareAmount).to.eq(parseEther('4'));
        });
      });

      describe('#convertToAssets', () => {
        let vault: UnderwriterVaultMock;
        let token: ERC20Mock;
        let baseT: ERC20Mock;
        let quoteT: ERC20Mock;
        let receiver: SignerWithAddress;

        beforeEach(async () => {
          const { callVault, putVault, base, quote, lp } = await loadFixture(
            vaultSetup,
          );
          vault = isCall ? callVault : putVault;
          token = isCall ? base : quote;
          baseT = base;
          quoteT = quote;
          receiver = lp;
        });

        it('if total supply is zero, revert due to zero shares', async () => {
          const shareAmount = parseEther('2');
          await expect(
            vault.convertToAssets(shareAmount),
          ).to.be.revertedWithCustomError(vault, 'Vault__ZeroShares');
        });

        it('if supply is non-zero and pricePerShare is one, withdrawn assets equals share amount', async () => {
          await setMaturities(vault);
          await addDeposit(vault, receiver, 2, baseT, quoteT);
          const shareAmount = parseEther('2');
          const assetAmount = await vault.convertToAssets(shareAmount);
          expect(assetAmount).to.eq(parseUnits('2', await token.decimals()));
        });

        it('if supply is non-zero and pricePerShare is 0.5, withdrawn assets equals half the share amount', async () => {
          await setMaturities(vault);
          await addDeposit(vault, receiver, 2, baseT, quoteT);
          await vault.increaseTotalLockedSpread(parseEther('1.0'));
          const assetAmount = await vault.convertToAssets(parseEther('2'));
          const assetAmountExpected = parseUnits('1.0', await token.decimals());
          expect(assetAmount).to.eq(assetAmountExpected);
        });
      });

      describe('#asset', () => {
        let vault: UnderwriterVaultMock;
        let token: ERC20Mock;
        const callDescription = {
          asset: 'base asset address',
          vaultType: 'callVault',
        };
        const putDescription = {
          asset: 'quote asset address',
          vaultType: 'callVault',
        };
        let testDescription = isCall ? callDescription : putDescription;
        it(`returns ${testDescription.asset} for ${testDescription.vaultType}`, async () => {
          const { callVault, putVault, base, quote } = await loadFixture(
            vaultSetup,
          );
          vault = isCall ? callVault : putVault;
          token = isCall ? base : quote;
          const assetAddress = await vault.asset();
          expect(assetAddress).to.eq(token.address);
        });
      });
    });
  }
});
