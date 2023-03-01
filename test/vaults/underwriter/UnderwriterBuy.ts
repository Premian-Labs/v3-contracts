import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { parseEther, formatEther, formatUnits } from 'ethers/lib/utils';
import { BigNumberish } from 'ethers';
import { vaultSetup } from './VaultSetup';

describe('#Vault contract', () => {
  it('properly initializes vault variables', async () => {
    const { vault, lastTimeStamp } = await loadFixture(vaultSetup);

    let minClevel: BigNumberish;
    let maxClevel: BigNumberish;
    let alphaClevel: BigNumberish;
    let hourlyDecayDiscount: BigNumberish;
    let minDTE: BigNumberish;
    let maxDTE: BigNumberish;
    let minDelta: BigNumberish;
    let maxDelta: BigNumberish;
    let _lastTradeTimestamp: BigNumberish;

    [minClevel, maxClevel, alphaClevel, hourlyDecayDiscount] =
      await vault.getClevelParams();

    expect(parseFloat(formatEther(minClevel))).to.eq(1.0);
    expect(parseFloat(formatEther(maxClevel))).to.eq(1.2);
    expect(parseFloat(formatEther(alphaClevel))).to.eq(3.0);
    expect(parseFloat(formatEther(hourlyDecayDiscount))).to.eq(0.005);

    [minDTE, maxDTE, minDelta, maxDelta] = await vault.getTradeBounds();

    expect(parseFloat(formatEther(minDTE))).to.eq(3.0);
    expect(parseFloat(formatEther(maxDTE))).to.eq(30.0);
    expect(parseFloat(formatEther(minDelta))).to.eq(0.1);
    expect(parseFloat(formatEther(maxDelta))).to.eq(0.7);

    _lastTradeTimestamp = await vault.getLastTradeTimestamp();
    // check that a timestamp was set
    expect(_lastTradeTimestamp).to.eq(lastTimeStamp);
    // check timestamp is in seconds epoch
    expect(_lastTradeTimestamp.toString().length).to.eq(10);
  });

  it('should properly initialize a new option pool', async () => {
    const { p, poolKey, poolAddress } = await loadFixture(vaultSetup);
    expect(await p.poolFactory.getPoolAddress(poolKey)).to.eq(poolAddress);
  });

  it('should properly hydrate accounts with funds', async () => {
    const { base, quote, deployer, caller, receiver, lp, trader } =
      await loadFixture(vaultSetup);
    expect(await base.balanceOf(deployer.address)).to.equal(parseEther('1000'));
    expect(await base.balanceOf(caller.address)).to.equal(parseEther('1000'));
    expect(await base.balanceOf(receiver.address)).to.equal(parseEther('1000'));
    expect(await base.balanceOf(lp.address)).to.equal(parseEther('1000'));
    expect(await base.balanceOf(trader.address)).to.equal(parseEther('1000'));
    expect(await quote.balanceOf(deployer.address)).to.equal(
      parseEther('1000000'),
    );
    expect(await quote.balanceOf(caller.address)).to.equal(
      parseEther('1000000'),
    );
    expect(await quote.balanceOf(receiver.address)).to.equal(
      parseEther('1000000'),
    );
    expect(await quote.balanceOf(lp.address)).to.equal(parseEther('1000000'));
    expect(await quote.balanceOf(trader.address)).to.equal(
      parseEther('1000000'),
    );
  });

  it('responds to mock oracle adapter query', async () => {
    const { oracleAdapter, base, quote } = await loadFixture(vaultSetup);
    const price = await oracleAdapter.quote(base.address, quote.address);
    expect(parseFloat(formatUnits(price, 18))).to.eq(1500);
  });

  it('responds to mock iv oracle query', async () => {
    const { volOracle, base } = await loadFixture(vaultSetup);
    const iv = await volOracle[
      'getVolatility(address,uint256,uint256,uint256)'
    ](base.address, parseEther('2500'), parseEther('2000'), parseEther('0.2'));
    expect(parseFloat(formatEther(iv))).to.eq(0.8054718161126052);
  });
});

describe('#buy functionality', () => {
  describe('#quote functionality', () => {
    it('determines the appropriate collateral amt', async () => {});

    it('reverts on no strike input', async () => {});

    it('checks that option has not expired', async () => {});

    it('gets a valid spot price', async () => {});

    it('gets a valid iv value', async () => {});

    describe('#isValidListing functionality', () => {
      it('reverts on invalid maturity bounds', async () => {});

      it('retrieves valid option delta', async () => {});

      it('reverts on invalid option delta bounds', async () => {});

      it('receives a valid option address', async () => {});

      it('returns addressZero for non existing pool', async () => {});
    });

    it('returns the proper blackscholes price', async () => {});

    it('calculates the proper mintingFee', async () => {});

    it('checks if the vault has sufficient funds', async () => {});

    describe('#cLevel functionality', () => {
      it('should have a totalSpread that is positive', async () => {});

      it('reverts if maxCLevel is not set properly', async () => {});

      it(' reverts if the C level alpha is not set properly', async () => {});

      it('used post quote/trade utilization', async () => {});

      it('ensures utilization never goes over 100%', async () => {});

      it('properly checks for last trade timestamp', async () => {});

      describe('#cLevel calculation', () => {
        it('will not exceed max c Level', async () => {});

        it('will properly adjust based on utilization', async () => {});
      });

      it('properly decays the c Level over time', async () => {});

      it('will not go below min c Level', async () => {});
    });
  });

  describe('#addListing functionality', () => {
    it('will insert maturity if it does not exist', async () => {});

    it('will properly add a strike only once', async () => {});

    it('will update the doublylinked list max maturity if needed', async () => {});
  });

  describe('#minting options', () => {
    it('should charge a fee to mint options', async () => {});

    it('should transfer collatera from the vault to the pool', async () => {});

    it('should send long contracts to the buyer', async () => {});

    it('should send short contracts to the vault', async () => {});
  });

  describe('#afterBuy', () => {
    //TODO: merge afterbuy from UnderwriterBuy.ts
  });
});
