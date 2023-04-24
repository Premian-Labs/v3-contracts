import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  addDeposit,
  addMockDeposit,
  callVault,
  vaultSetup,
} from '../UnderwriterVault.fixture';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { formatEther, parseEther, parseUnits } from 'ethers/lib/utils';
import { setMaturities } from '../UnderwriterVault.fixture';
import {
  ERC20Mock,
  IERC20__factory,
  UnderwriterVaultMock,
} from '../../../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { latest, ONE_DAY, ONE_YEAR } from '../../../../utils/time';
import {
  setupBeforeTokenTransfer,
  setup,
  testsFeeVars,
} from './UnderwriterVault.fees';

describe('#ERC4626 overridden functions', () => {
  for (const isCall of [true, false]) {
    describe(isCall ? 'call' : 'put', () => {
      describe('#_totalAssets', () => {
        let vault: UnderwriterVaultMock;
        let token: ERC20Mock;
        const tests = [
          { totalAssets: 1 },
          { totalAssets: 1.1 },
          { totalAssets: 590.7 },
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

        it('maxWithdraw should return the available assets since the available assets are less than the max transferable', async () => {
          const { callVault, receiver, base, quote } = await loadFixture(
            vaultSetup,
          );
          const timestamp = await latest();
          await callVault.setTimestamp(timestamp);
          await setMaturities(callVault);
          await addDeposit(callVault, receiver, 3, base, quote);

          await callVault.increaseTotalLockedSpread(parseEther('0.1'));
          await callVault.increaseTotalLockedAssets(parseEther('0.5'));

          // incrementing time by a day does not have an effect on the max withdrawable assets
          await callVault.setTimestamp(timestamp + ONE_DAY);
          const assetAmount = await callVault.maxWithdraw(receiver.address);

          expect(assetAmount).to.eq(parseEther('2.4'));
        });

        it('maxWithdraw should return the max transferable assets (test 1)', async () => {
          const { callVault, caller, receiver, base, quote } =
            await loadFixture(vaultSetup);
          const timestamp = await latest();
          await callVault.setTimestamp(timestamp);

          await setMaturities(callVault);
          await addDeposit(callVault, receiver, 2, base, quote);

          await callVault.setTimestamp(timestamp + ONE_DAY);

          const assetAmount = await callVault.maxWithdraw(receiver.address);
          expect(assetAmount).to.eq(parseEther('1.999890410958904110'));
        });

        it('maxWithdraw should return the max transferable assets (test 2)', async () => {
          const { callVault, caller, receiver, base, quote } =
            await loadFixture(vaultSetup);
          const timestamp = await latest();
          await callVault.setTimestamp(timestamp);

          await setMaturities(callVault);
          await addDeposit(callVault, caller, 8, base, quote);
          await addDeposit(callVault, receiver, 2, base, quote);
          await callVault.increaseTotalLockedSpread(parseEther('0.0'));
          await callVault.increaseTotalLockedAssets(parseEther('0.5'));

          await callVault.setTimestamp(timestamp + ONE_DAY);

          const assetAmount = await callVault.maxWithdraw(receiver.address);
          expect(assetAmount).to.eq(parseEther('1.999890410958904110'));
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

        it('should return max transferable shares of the caller', async () => {
          // assets caller: 2.3 * 1.5
          // tax caller: 2.3 * 1.5 * 0.05 * 0.25 = 0.43125
          // maxWithdrawable = assets - tax = 3.406875

          let test = {
            shares: 2.3,
            pps: 1.5,
            ppsUser: 1.2,
            totalSupply: 2.5,
            managementFeeRate: 0.0,
            performanceFeeRate: 0.05,
          };

          let { vault, caller } = await setup(isCall, test);

          await vault.setPerformanceFeeRate(
            parseEther(test.performanceFeeRate.toString()),
          );
          await vault.setManagementFeeRate(
            parseEther(test.managementFeeRate.toString()),
          );

          const assetAmount = await vault.maxRedeem(caller.address);
          expect(assetAmount).to.eq(parseEther('2.27125'));
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

      describe('#transfer', () => {
        it('transfer should update the netUserDeposit of the receiver and timeOfDeposit', async () => {
          const test = testsFeeVars[0];
          const { vault, caller, receiver } = await setupBeforeTokenTransfer(
            true,
            test,
          );
          const addressToken = await vault.thisAddress();
          const vaultToken = IERC20__factory.connect(addressToken, caller);

          await vault.setTimestamp(test.timestamp);
          await vaultToken
            .connect(caller)
            .transfer(
              receiver.address,
              parseEther(test.transferAmount.toString()),
            );

          expect(await vault.getTimeOfDeposit(receiver.address)).to.eq(
            test.timestamp,
          );
          expect(await vault.getNetUserDeposit(receiver.address)).to.eq(
            parseEther(test.netUserDepositReceiverAfter.toString()),
          );
          expect(await vault.balanceOf(receiver.address)).to.eq(
            parseEther('0.1'),
          );

          await vault.setTimestamp(test.timestamp + ONE_YEAR);

          await vaultToken
            .connect(caller)
            .transfer(
              receiver.address,
              parseEther(test.transferAmount.toString()),
            );

          expect(await vault.getTimeOfDeposit(receiver.address)).to.eq(
            test.timestamp + 0.5 * ONE_YEAR,
          );
          expect(await vault.getNetUserDeposit(receiver.address)).to.eq(
            parseEther('1.4'),
          );
          expect(await vault.balanceOf(receiver.address)).to.eq(
            parseEther('0.2'),
          );
        });
      });

      describe('#deposit', () => {
        it('should update fee-related numbers', async () => {
          const test = testsFeeVars[0];
          const { vault, caller, token } = await setupBeforeTokenTransfer(
            true,
            test,
          );
          const assetAmount = parseUnits('1.4', await token.decimals());
          await token.mint(caller.address, assetAmount);
          await token.connect(caller).approve(vault.address, assetAmount);
          await vault.setTimestamp(test.timestamp);
          await vault.connect(caller).deposit(assetAmount, caller.address);
          // 1.1 + 1.4 = 2.5
          expect(await vault.getNetUserDeposit(caller.address)).to.eq(
            parseEther('2.5'),
          );
          // (1.1 * 3000000000 + 1.4 * 3000086400) / 2.5
          expect(await vault.getTimeOfDeposit(caller.address)).to.eq(
            3000048384,
          );
          expect(await vault.balanceOf(caller.address)).to.eq(
            parseEther('2.5'),
          );
        });
      });

      describe('#withdraw', () => {
        it('should update all fee-related numbers', async () => {
          const test = testsFeeVars[0];
          const { vault, caller, token } = await setupBeforeTokenTransfer(
            true,
            test,
          );

          const assetAmount = parseUnits('0.4', await token.decimals());
          await vault.setTimestamp(test.timestamp);
          await vault
            .connect(caller)
            .withdraw(assetAmount, caller.address, caller.address);
          expect(await vault.getNetUserDeposit(caller.address)).to.eq(
            '699978082191780821',
          );
          expect(await vault.getTimeOfDeposit(caller.address)).to.eq(
            3000000000,
          );
          expect(await vault.balanceOf(caller.address)).to.eq(
            '699978082191780822',
          );
        });
      });
    });
  }
});
