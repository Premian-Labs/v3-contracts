import { expect } from 'chai';
import { ethers } from 'hardhat';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getContractAddress } from 'ethers/lib/utils';
import {
  ERC20Mock,
  ERC20Mock__factory,
  UnderwriterVaultMock,
  UnderwriterVaultMock__factory,
  UnderwriterVaultProxy__factory,
  UnderwriterVaultProxy,
  VolatilityOracleMock,
  ProxyUpgradeableOwnable,
  VolatilityOracleMock__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../../typechain';
import {
  parseEther,
  parseUnits,
  formatEther,
  formatUnits,
} from 'ethers/lib/utils';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { BigNumberish } from 'ethers';

describe('UnderwriterVault', () => {
  let deployer: SignerWithAddress;
  let caller: SignerWithAddress;
  let receiver: SignerWithAddress;
  let lp: SignerWithAddress;
  let trader: SignerWithAddress;

  let vaultImpl: UnderwriterVaultMock;
  let vaultProxy: UnderwriterVaultProxy;
  let vault: UnderwriterVaultMock;

  interface Clevel {
    minClevel: BigNumberish;
    maxClevel: BigNumberish;
    alphaClevel: BigNumberish;
    hourlyDecayDiscount: BigNumberish;
  }

  interface TradeBounds {
    maxDTE: BigNumberish;
    minDTE: BigNumberish;
    minDelta: BigNumberish;
    maxDelta: BigNumberish;
  }

  let base: ERC20Mock;
  let quote: ERC20Mock;
  let long: ERC20Mock;
  let short: ERC20Mock;

  let oracleAdapter: MockContract;
  let factory: MockContract;
  let volOracle: VolatilityOracleMock;
  let volOracleProxy: ProxyUpgradeableOwnable;

  const log = true;

  describe('#Vault contract', () => {
    async function vaultSetup() {
      [deployer, caller, receiver, lp, trader] = await ethers.getSigners();

      base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
      quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);
      long = await new ERC20Mock__factory(deployer).deploy('Long', 18);
      short = await new ERC20Mock__factory(deployer).deploy('Short', 18);

      await base.deployed();
      await quote.deployed();
      await long.deployed();
      await short.deployed();

      // Hydrate all accounts with WETH and USDC
      await base.mint(deployer.address, parseEther('1000'));
      await quote.mint(deployer.address, parseEther('1000000'));

      await base.mint(caller.address, parseEther('1000'));
      await quote.mint(caller.address, parseEther('1000000'));

      await base.mint(receiver.address, parseEther('1000'));
      await quote.mint(receiver.address, parseEther('1000000'));

      await base.mint(lp.address, parseEther('1000'));
      await quote.mint(lp.address, parseEther('1000000'));

      await base.mint(trader.address, parseEther('1000'));
      await quote.mint(trader.address, parseEther('1000000'));

      // Mock Oracle Adapter setup
      oracleAdapter = await deployMockContract(deployer, [
        'function quote(address, address) external view returns (uint256)',
      ]);

      await oracleAdapter.mock.quote.returns(parseUnits('1500', 8));

      if (log)
        console.log(
          `Mock oracelAdapter Implementation : ${oracleAdapter.address}`,
        );

      // Mock Volatility Oracle setup
      const impl = await new VolatilityOracleMock__factory(deployer).deploy();

      volOracleProxy = await new ProxyUpgradeableOwnable__factory(
        deployer,
      ).deploy(impl.address);

      volOracle = VolatilityOracleMock__factory.connect(
        volOracleProxy.address,
        deployer,
      );

      await volOracle
        .connect(deployer)
        .addWhitelistedRelayers([deployer.address]);

      const tau = [
        0.0027397260273972603, 0.03561643835616438, 0.09315068493150686,
        0.16986301369863013, 0.4191780821917808,
      ].map((el) => Math.floor(el * 10 ** 12));

      const theta = [
        0.0017692409901229372, 0.01916765969267577, 0.050651452629040784,
        0.10109715579595925, 0.2708994887970898,
      ].map((el) => Math.floor(el * 10 ** 12));

      const psi = [
        0.037206384846952066, 0.0915623614722959, 0.16107355519602318,
        0.2824760899898832, 0.35798035117937516,
      ].map((el) => Math.floor(el * 10 ** 12));

      const rho = [
        1.3478910000157727e-8, 2.0145423645807155e-6, 2.910345029369492e-5,
        0.0003768214425074357, 0.0002539234691761822,
      ].map((el) => Math.floor(el * 10 ** 12));

      const tauHex = await volOracle.formatParams(tau as any);
      const thetaHex = await volOracle.formatParams(theta as any);
      const psiHex = await volOracle.formatParams(psi as any);
      const rhoHex = await volOracle.formatParams(rho as any);

      await volOracle
        .connect(deployer)
        .updateParams([base.address], [tauHex], [thetaHex], [psiHex], [rhoHex]);

      if (log) console.log(`volOracle Address : ${volOracle.address}`);

      // Mock Pool setup
      const transactionCount = await deployer.getTransactionCount();
      const poolAddress = getContractAddress({
        from: deployer.address,
        nonce: transactionCount,
      });

      // Mock Option Pool setup
      factory = await deployMockContract(deployer, [
        'function getPoolAddress () external view returns (address)',
      ]);
      await factory.mock.getPoolAddress.returns(poolAddress);
      if (log) console.log(`Mock Pool Address : ${poolAddress}`);

      // Mock Vault setup
      vaultImpl = await new UnderwriterVaultMock__factory(deployer).deploy(
        volOracle.address,
        factory.address,
      );
      await vaultImpl.deployed();
      if (log)
        console.log(`UnderwriterVault Implementation : ${vaultImpl.address}`);

      const _cLevelParams: Clevel = {
        minClevel: parseEther('1.0'),
        maxClevel: parseEther('1.2'),
        alphaClevel: parseEther('3.0'),
        hourlyDecayDiscount: parseEther('0.005'),
      };

      const _tradeBounds: TradeBounds = {
        maxDTE: parseEther('30'),
        minDTE: parseEther('3'),
        minDelta: parseEther('0.1'),
        maxDelta: parseEther('0.7'),
      };

      const timeStamp = new Date().getTime();
      // Vault Proxy setup
      vaultProxy = await new UnderwriterVaultProxy__factory(deployer).deploy(
        vaultImpl.address,
        base.address,
        quote.address,
        oracleAdapter.address,
        'WETH Vault',
        'WETH',
        true,
        _cLevelParams,
        _tradeBounds,
        0,
        timeStamp,
      );
      await vaultProxy.deployed();
      vault = UnderwriterVaultMock__factory.connect(
        vaultProxy.address,
        deployer,
      );
      if (log) console.log(`UnderwriterVaultProxy : ${vaultProxy.address}`);

      return { base, quote, vault, volOracle, oracleAdapter };
    }

    it('initializes vault variables', async () => {
      const { vault } = await loadFixture(vaultSetup);

      let minClevel: BigNumberish;
      let maxClevel: BigNumberish;
      let alphaClevel: BigNumberish;
      let hourlyDecayDiscount: BigNumberish;

      [minClevel, maxClevel, alphaClevel, hourlyDecayDiscount] =
        await vault.getClevelParams();

      expect(parseFloat(formatEther(minClevel))).to.eq(1.0);
      expect(parseFloat(formatEther(maxClevel))).to.eq(1.2);
      expect(parseFloat(formatEther(alphaClevel))).to.eq(3.0);
      expect(parseFloat(formatEther(hourlyDecayDiscount))).to.eq(0.005);

      let minDTE: BigNumberish;
      let maxDTE: BigNumberish;
      let minDelta: BigNumberish;
      let maxDelta: BigNumberish;

      [minDTE, maxDTE, minDelta, maxDelta] = await vault.getTradeBounds();

      expect(parseFloat(formatEther(minDTE))).to.eq(3.0);
      expect(parseFloat(formatEther(maxDTE))).to.eq(30.0);
      expect(parseFloat(formatEther(minDelta))).to.eq(0.1);
      expect(parseFloat(formatEther(maxDelta))).to.eq(0.7);
    });

    describe('#buy functionality', () => {
      it('responds to mock iv oracle query', async () => {
        const { volOracle, base } = await loadFixture(vaultSetup);
        const iv = await volOracle[
          'getVolatility(address,uint256,uint256,uint256)'
        ](
          base.address,
          parseEther('2500'),
          parseEther('2000'),
          parseEther('0.2'),
        );
        expect(parseFloat(formatEther(iv))).to.eq(0.8054718161126052);
      });
      it('responds to mock oracle adapter query', async () => {
        const { oracleAdapter, base, quote } = await loadFixture(vaultSetup);
        const price = await oracleAdapter.quote(base.address, quote.address);
        expect(parseFloat(formatUnits(price, 8))).to.eq(1500);
      });
      it('should have a totalSpread that is positive', async () => {});

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
          it('reverts if maxCLevel is not set properly', async () => {});

          it(' reverts if the C level alpha is not set properly', async () => {});

          it('used post quote/trade utilization', async () => {});

          it('ensures utilization never goes over 100%', async () => {});

          it('properly checks for last trade timestamp', async () => {
            //TODO: add code for initializing lastTradeTimestamp on deployment
          });

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
  });
});
