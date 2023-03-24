import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { addMockDeposit, increaseTotalShares, vaultSetup } from '../VaultSetup';
import {
  formatEther,
  formatUnits,
  parseEther,
  parseUnits,
} from 'ethers/lib/utils';
import { expect } from 'chai';
import {
  getValidMaturity,
  increaseTo,
  latest,
  ONE_DAY,
  ONE_HOUR,
  ONE_WEEK,
} from '../../../../utils/time';
import {
  ERC20Mock,
  IPoolMock,
  UnderwriterVaultMock,
} from '../../../../typechain';
import { BigNumber, ethers } from 'ethers';
import { setMaturities } from '../VaultSetup';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { MockContract } from '@ethereum-waffle/mock-contract';
import { PoolUtil } from '../../../../utils/PoolUtil';
import { PoolKey, TokenType } from '../../../../utils/sdk/types';
import exp from 'constants';
import { start } from 'repl';
import { Sign } from 'crypto';

let startTime: number;
let vault: UnderwriterVaultMock;
let token: ERC20Mock;

describe('UnderwriterVault.fees', () => {
  describe('#_chargeManagementFees', () => {
    startTime = 10000000;
    const tests = [
      {
        totalAssets: 11.2,
        lastFeeEventTimestamp: startTime - ONE_DAY,
        timestamp: startTime + ONE_DAY,
        feesCollected: 1,
        managementFeeRate: 0.01,
        feesCollectedAfter: 1 + (11.2 * 0.01 * 2) / 365,
      },
      {
        totalAssets: 1.2,
        lastFeeEventTimestamp: startTime - ONE_DAY,
        timestamp: startTime + ONE_DAY,
        feesCollected: 0.0123,
        managementFeeRate: 0.0,
        feesCollectedAfter: 0.0123,
      },
      {
        totalAssets: 501.3,
        lastFeeEventTimestamp: startTime - ONE_DAY,
        timestamp: startTime + 6 * ONE_HOUR,
        feesCollected: 0.0123,
        managementFeeRate: 0.05,
        feesCollectedAfter: 0.0123 + (501.3 * 0.05 * (1 + 1 / 4)) / 365,
      },
    ];

    tests.forEach(async (test) => {
      async function setup() {
        let { callVault } = await loadFixture(vaultSetup);
        vault = callVault;
        await vault.setFeesCollected(parseEther(test.feesCollected.toString()));
        await vault.setLastFeeEventTimestamp(test.lastFeeEventTimestamp);
        await vault.setManagementFeeRate(
          parseEther(test.managementFeeRate.toString()),
        );
        await vault.chargeManagementFees(
          test.timestamp,
          parseEther(test.totalAssets.toString()),
        );
      }
      it(`fees collected after charging equals ${test.feesCollectedAfter}`, async () => {
        await loadFixture(setup);
        const feesCollected = parseFloat(
          formatEther(await vault.getFeesCollected()),
        );
        const delta = 1e-16;
        expect(feesCollected).to.be.closeTo(test.feesCollectedAfter, delta);
      });
      it(`lastFeeEventTimestamp equals ${test.timestamp}`, async () => {
        expect(await vault.getLastFeeEventTimestamp()).to.eq(test.timestamp);
      });
    });
  });

  async function setup(isCall: boolean, test: any) {
    let { callVault, putVault, base, quote, caller } = await loadFixture(
      vaultSetup,
    );

    vault = isCall ? callVault : putVault;
    token = isCall ? base : quote;

    // set pps and totalSupply vault
    const totalSupply = parseEther(test.totalSupply.toString());
    await increaseTotalShares(
      vault,
      parseFloat((test.totalSupply - test.shares).toFixed(12)),
    );
    const pps = parseEther(test.pps.toString());
    const vaultDeposit = parseEther((test.pps * test.totalSupply).toFixed(12));
    await token.mint(vault.address, vaultDeposit);

    // set pps and shares user
    const userShares = parseEther(test.shares.toString());
    await vault.mintMock(caller.address, userShares);
    const userDeposit = parseEther((test.shares * test.ppsUser).toFixed(12));
    await vault.setNetUserDeposit(caller.address, userDeposit);
    //const ppsUser = parseEther(test.ppsUser.toString());
    //const ppsAvg = await vault.getAveragePricePerShare(caller.address);
    //expect(ppsAvg).to.eq(ppsUser);
    expect(await vault.totalSupply()).to.eq(totalSupply);
    expect(await vault.getPricePerShare()).to.eq(pps);

    return { vault, caller };
  }

  describe('#_getAveragePricePerShare', () => {
    const tests = [
      {
        shares: 1.1,
        totalSupply: 2.2,
        pps: 1.0,
        ppsUser: 1,
      },
      {
        shares: 2.3,
        totalSupply: 2.5,
        pps: 1.5,
        ppsUser: 1.2,
      },
    ];
    let isCall = true;

    tests.forEach(async (test) => {
      it(`userShares ${test.shares}, userDeposit ${
        test.ppsUser * test.shares
      }, ppsVault ${test.pps}, then ppsUser equals ${test.pps}`, async () => {
        const { vault, caller } = await setup(isCall, test);
        const ppsUser = parseFloat(
          formatEther(await vault.getAveragePricePerShare(caller.address)),
        );
        expect(ppsUser).to.eq(test.ppsUser);
      });
    });
  });

  async function setupMaxTransferable(isCall: boolean, test: any) {
    let { vault, caller } = await setup(isCall, test);
    await vault.setPerformanceFeeRate(
      parseEther(test.performanceFeeRate.toString()),
    );
    return { vault, caller };
  }

  describe('#_maxTransferableShares', () => {
    const tests = [
      {
        shares: 1.1,
        pps: 1.0,
        ppsUser: 1,
        totalSupply: 2.2,
        maxTransferable: 1.1,
        performanceFeeRate: 0.01,
      },
      {
        shares: 0.0,
        pps: 1.3,
        ppsUser: 1.3,
        totalSupply: 2.2,
        maxTransferable: 0.0,
        performanceFeeRate: 0.01,
      },
      {
        shares: 2.3,
        pps: 1.5,
        ppsUser: 1.2,
        totalSupply: 2.5,
        maxTransferable: 2.27125,
        performanceFeeRate: 0.05,
      },
    ];
    let isCall = true;

    tests.forEach(async (test) => {
      it(`userShares ${test.shares}, ppsUser ${test.ppsUser}, ppsVault ${test.pps}, then maxTransferableShares equals ${test.maxTransferable}`, async () => {
        const { vault, caller } = await setupMaxTransferable(isCall, test);
        const maxTransferable = await vault.maxTransferableShares(
          caller.address,
        );
        expect(parseFloat(formatEther(maxTransferable))).to.eq(
          test.maxTransferable,
        );
      });
    });
  });

  describe('#_beforeTokenTransfer', () => {
    const tests = [
      {
        shares: 1.1,
        pps: 1.0,
        ppsUser: 1.0,
        totalSupply: 2.2,
        performanceFeeRate: 0.01,
        feesCollectedInitial: 0.1,
        feesCollected: 0.1,
        transferAmount: 0.1,
        sharesAfter: 1.1,
        netUserDepositReceiver: 1.2,
        netUserDepositReceiverAfter: 1.3,
        netUserDepositCallerAfter: 1.0,
      },
      {
        shares: 2.3,
        pps: 1.5,
        ppsUser: 1.2,
        totalSupply: 2.5,
        performanceFeeRate: 0.05,
        feesCollectedInitial: 0.1,
        feesCollected: 0.1230625,
        transferAmount: 1.23,
        sharesAfter: 2.284625,
        netUserDepositReceiver: 1.2,
        netUserDepositReceiverAfter: 3.045,
        netUserDepositCallerAfter: 1.26555,
      },
    ];
    let vault: UnderwriterVaultMock;
    let caller: SignerWithAddress;
    let receiver: SignerWithAddress;
    let token: ERC20Mock;
    let isCall = true;

    async function setupBeforeTokenTransfer(isCall: boolean, test: any) {
      let {
        callVault,
        putVault,
        base,
        quote,
        caller: _caller,
        receiver: _receiver,
      } = await loadFixture(vaultSetup);

      vault = isCall ? callVault : putVault;
      token = isCall ? base : quote;
      caller = _caller;
      receiver = _receiver;

      // set pps and totalSupply vault
      const totalSupply = parseEther(test.totalSupply.toString());
      await increaseTotalShares(
        vault,
        parseFloat((test.totalSupply - test.shares).toFixed(12)),
      );
      const pps = parseEther(test.pps.toString());
      const vaultDeposit = parseEther(
        (test.pps * test.totalSupply).toFixed(12),
      );
      await token.mint(vault.address, vaultDeposit);
      // if we dont ad this amount the pps will be lower due to collected fees
      await token.mint(
        vault.address,
        parseEther(test.feesCollectedInitial.toString()),
      );
      await vault.setFeesCollected(
        parseEther(test.feesCollectedInitial.toString()),
      );
      // set pps and shares user caller
      const userShares = parseEther(test.shares.toString());
      await vault.mintMock(caller.address, userShares);
      const userDeposit = parseEther((test.shares * test.ppsUser).toFixed(12));
      await vault.setNetUserDeposit(caller.address, userDeposit);

      // check pps is as expected
      const ppsUser = parseEther(test.ppsUser.toString());
      const ppsAvg = await vault.getAveragePricePerShare(caller.address);
      expect(ppsAvg).to.eq(ppsUser);

      await vault.setNetUserDeposit(
        receiver.address,
        parseEther(test.netUserDepositReceiver.toString()),
      );

      expect(await vault.totalSupply()).to.eq(totalSupply);
      expect(await vault.getPricePerShare()).to.eq(pps);

      await vault.setPerformanceFeeRate(
        parseEther(test.performanceFeeRate.toString()),
      );
      return { vault, caller, receiver };
    }

    tests.forEach(async (test) => {
      it(`the balanceOf caller equals ${test.sharesAfter}`, async () => {
        let { vault, caller, receiver } = await setupBeforeTokenTransfer(
          isCall,
          test,
        );

        await vault.beforeTokenTransfer(
          caller.address,
          receiver.address,
          parseEther(test.transferAmount.toString()),
        );

        const balanceAfter = parseFloat(
          formatEther(await vault.balanceOf(caller.address)),
        );
        expect(balanceAfter).to.eq(test.sharesAfter);
      });
      it(`feesCollected should equal ${test.feesCollected}`, async () => {
        const feesAfter = parseFloat(
          formatEther(await vault.getFeesCollected()),
        );
        expect(feesAfter).to.eq(test.feesCollected);
      });
      it('vault pps should stay constant', async () => {
        const pps = parseFloat(formatEther(await vault.getPricePerShare()));
        expect(pps).to.eq(test.pps);
      });
      it(`netUserDeposit of caller should equal ${test.netUserDepositCallerAfter}`, async () => {
        const netUserDeposit = parseFloat(
          formatEther(await vault.getNetUserDeposit(caller.address)),
        );
        const delta = 1e-8;
        expect(netUserDeposit).to.be.closeTo(
          test.netUserDepositCallerAfter,
          delta,
        );
      });
      it(`netUserDeposit of receiver should equal ${test.netUserDepositReceiverAfter}`, async () => {
        const netUserDeposit = parseFloat(
          formatEther(await vault.getNetUserDeposit(receiver.address)),
        );
        const delta = 1e-8;
        expect(netUserDeposit).to.be.closeTo(
          test.netUserDepositReceiverAfter,
          delta,
        );
      });
    });

    it('no effect if address from is zero address', async () => {
      let test = tests[1];
      let { vault, receiver } = await setupBeforeTokenTransfer(isCall, test);
      const callerAddress = ethers.constants.AddressZero;
      await vault.beforeTokenTransfer(
        callerAddress,
        receiver.address,
        parseEther(test.transferAmount.toString()),
      );
      const netUserDepositCaller = parseFloat(
        formatEther(await vault.getNetUserDeposit(callerAddress)),
      );
      expect(netUserDepositCaller).to.eq(0);

      const netUserDepositReceiver = parseFloat(
        formatEther(await vault.getNetUserDeposit(receiver.address)),
      );
      expect(netUserDepositReceiver).to.eq(test.netUserDepositReceiver);
    });

    it('no effect if address to is zero address', async () => {
      let test = tests[1];
      let { vault, caller } = await setupBeforeTokenTransfer(isCall, test);
      const receiverAddress = ethers.constants.AddressZero;

      await vault.beforeTokenTransfer(
        caller.address,
        receiverAddress,
        parseEther(test.transferAmount.toString()),
      );

      const netUserDepositReceiver = parseFloat(
        formatEther(await vault.getNetUserDeposit(receiverAddress)),
      );
      expect(netUserDepositReceiver).to.eq(0);

      const netUserDepositCaller = parseFloat(
        formatEther(await vault.getNetUserDeposit(caller.address)),
      );
      expect(netUserDepositCaller).to.eq(2.76);
    });

    it('revert if transfer amount is too high', async () => {
      let test = tests[1];
      let { vault, caller, receiver } = await setupBeforeTokenTransfer(
        isCall,
        test,
      );
      await expect(
        vault.beforeTokenTransfer(
          caller.address,
          receiver.address,
          parseEther((2.27126).toString()),
        ),
      ).to.be.revertedWithCustomError(
        vault,
        'ERC20Base__TransferExceedsBalance',
      );
      // check that this passes
      await vault.beforeTokenTransfer(
        caller.address,
        receiver.address,
        parseEther((2.27125).toString()),
      );
    });

    it('if receiver address is the vault address the netUserDeposit should not be updated', async () => {
      let test = tests[1];
      let { vault, caller } = await setupBeforeTokenTransfer(isCall, test);

      await vault.beforeTokenTransfer(
        caller.address,
        vault.address,
        parseEther(test.transferAmount.toString()),
      );

      const netUserDepositReceiver = parseFloat(
        formatEther(await vault.getNetUserDeposit(vault.address)),
      );
      expect(netUserDepositReceiver).to.eq(0);

      const netUserDepositCaller = parseFloat(
        formatEther(await vault.getNetUserDeposit(caller.address)),
      );
      expect(netUserDepositCaller).to.eq(test.netUserDepositCallerAfter);
    });
  });

  let isCall: boolean = true;

  describe('#maxWithdraw', () => {
    it('maxWithdraw should revert for a zero address', async () => {
      const { callVault, base, quote } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addMockDeposit(callVault, 2, base, quote);
      await expect(
        callVault.maxWithdraw(ethers.constants.AddressZero),
      ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
    });

    let test = {
      shares: 2.3,
      pps: 1.5,
      ppsUser: 1.2,
      totalSupply: 2.5,
      maxTransferable: 2.27125,
      performanceFeeRate: 0.05,
    };

    it('should return maxTransferableShares * pricePerShare as sufficient funds are available', async () => {
      const { vault, caller } = await setupMaxTransferable(isCall, test);
      //await setMaturities(vault);
      //await vault.increaseTotalLockedSpread(parseEther('0.1'));
      //await vault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await vault.maxWithdraw(caller.address);

      // assets: 2.3 * 1.5
      // tax: 2.3 * 1.5 * 0.05 * 0.25
      // maxWithdrawable = assets - tax = 3.406875
      expect(assetAmount).to.eq(parseEther('3.406875'));
    });

    it('should return available assets', async () => {
      const { vault, caller } = await setupMaxTransferable(isCall, test);
      await setMaturities(vault);
      await vault.increaseTotalLockedSpread(parseEther('0.2'));
      await vault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await vault.maxWithdraw(caller.address);
      // assets: 2.3 * 1.5 = 3.45
      // tax: 2.3 * 1.5 * 0.05 * 0.25
      // maxWithdrawable = assets - tax = 3.406875
      //
      expect(assetAmount).to.eq(parseEther('3.15'));
    });

    it('maxWithdraw should return the available assets for a non-zero address', async () => {
      const { callVault, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );

      await setMaturities(callVault);
      await addMockDeposit(callVault, 3, base, quote, 3, receiver.address);
      await callVault.increaseTotalLockedSpread(parseEther('0.1'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await callVault.maxWithdraw(receiver.address);

      expect(assetAmount).to.eq(parseEther('2.4'));
    });

    it('maxWithdraw should return the assets the receiver owns', async () => {
      const { callVault, caller, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 8, base, quote, 8, caller.address);
      await addMockDeposit(callVault, 2, base, quote, 2, receiver.address);
      await callVault.increaseTotalLockedSpread(parseEther('0.0'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await callVault.maxWithdraw(receiver.address);
      expect(assetAmount).to.eq(parseEther('2'));
    });

    it('maxWithdraw should return the assets the receiver owns since there are sufficient funds', async () => {
      const { callVault, caller, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 7, base, quote, 7, caller.address);
      await addMockDeposit(callVault, 2, base, quote, 2, receiver.address);
      await callVault.increaseTotalLockedSpread(parseEther('0.1'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = parseFloat(
        formatEther(await callVault.maxWithdraw(receiver.address)),
      );
      expect(assetAmount).to.be.closeTo(1.977777777777777, 0.00000001);
    });
  });
});
