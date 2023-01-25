import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { ERC20Mock, ERC20Mock__factory, IPool__factory } from '../../typechain';
import { parseEther } from 'ethers/lib/utils';
import { PoolUtil } from '../../utils/PoolUtil';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { ONE_MONTH } from '../../utils/constants';
import { now, revertToSnapshotAfterEach } from '../../utils/time';

describe('PoolFactory', () => {
  let deployer: SignerWithAddress;

  let p: PoolUtil;

  let base: ERC20Mock;
  let underlying: ERC20Mock;
  let baseOracle: MockContract;
  let underlyingOracle: MockContract;

  let strike = parseEther('1000');
  let maturity: number;

  before(async () => {
    [deployer] = await ethers.getSigners();

    underlying = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    base = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    p = await PoolUtil.deploy(deployer, underlying.address, true, true);

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer () external view returns (int)',
      'function decimals () external view returns (uint8)',
    ]);

    underlyingOracle = await deployMockContract(deployer as any, [
      'function latestAnswer () external view returns (int)',
      'function decimals () external view returns (uint8)',
    ]);

    maturity = (await now()) + ONE_MONTH;
  });

  revertToSnapshotAfterEach(async () => {});

  describe('#isPoolDeployed', () => {
    it('should return false if no pool has been deployed with given parameters', async () => {
      expect(
        await p.poolFactory.isPoolDeployed(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          true,
        ),
      ).to.be.false;
    });

    it('should return true if a pool with given parameters has been deployed', async () => {
      await p.poolFactory.deployPool(
        base.address,
        underlying.address,
        baseOracle.address,
        underlyingOracle.address,
        strike,
        maturity,
        true,
      );

      expect(
        await p.poolFactory.isPoolDeployed(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          true,
        ),
      ).to.be.true;
    });
  });

  describe('#deployPool', () => {
    it('should properly deploy the pool', async () => {
      const tx = await p.poolFactory.deployPool(
        base.address,
        underlying.address,
        baseOracle.address,
        underlyingOracle.address,
        strike,
        maturity,
        true,
      );

      const r = await tx.wait(1);
      const poolAddress = (r as any).events[0].args.poolAddress;

      const pool = IPool__factory.connect(poolAddress, deployer);
      const poolSettings = await pool.getPoolSettings();

      expect([
        poolSettings.base,
        poolSettings.underlying,
        poolSettings.baseOracle,
        poolSettings.underlyingOracle,
        poolSettings.strike,
        poolSettings.maturity,
        poolSettings.isCallPool,
      ]).to.deep.eq([
        base.address,
        underlying.address,
        baseOracle.address,
        underlyingOracle.address,
        strike,
        maturity,
        true,
      ]);
    });

    it('should revert if base and underlying are identical', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          base.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          true,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__IdenticalAddresses',
      );
    });

    it('should revert if baseOracle and underlyingOracle are identical', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          baseOracle.address,
          strike,
          maturity,
          true,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__IdenticalAddresses',
      );
    });

    it('should revert if maturity is invalid', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          (await now()) - 1,
          true,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__InvalidMaturity',
      );

      // ToDo : Check maturity increments
    });

    it('should revert if strike is invalid', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          0,
          maturity,
          true,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__InvalidStrike',
      );

      // ToDo : Check strike increments
    });

    it('should revert if pool has already been deployed', async () => {
      await p.poolFactory.deployPool(
        base.address,
        underlying.address,
        baseOracle.address,
        underlyingOracle.address,
        strike,
        maturity,
        true,
      );

      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          true,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__PoolAlreadyDeployed',
      );
    });
  });
});
