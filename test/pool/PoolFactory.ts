import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  ERC20Mock,
  ERC20Mock__factory,
  IPoolFactory,
  IPoolFactory__factory,
} from '../../typechain';
import { parseEther } from 'ethers/lib/utils';
import { PoolUtil } from '../../utils/PoolUtil';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { now, revertToSnapshotAfterEach } from '../../utils/time';

describe('PoolFactory', () => {
  let deployer: SignerWithAddress;

  let p: PoolUtil;
  let poolFactoryInterface: IPoolFactory;

  let base: ERC20Mock;
  let underlying: ERC20Mock;
  let baseOracle: MockContract;
  let underlyingOracle: MockContract;

  let strike = parseEther('1000'); // ATM
  let maturity = 1645776000; // Fri Feb 25 2022 08:00:00 GMT+0000
  let blockTimestamp: number;

  before(async () => {
    [deployer] = await ethers.getSigners();

    underlying = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    base = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    p = await PoolUtil.deploy(deployer, underlying.address, true, true);

    poolFactoryInterface = IPoolFactory__factory.connect(
      ethers.constants.AddressZero,
      deployer,
    );

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.latestAnswer.returns(100000000);
    await baseOracle.mock.decimals.returns(8);

    underlyingOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await underlyingOracle.mock.latestAnswer.returns(100000000000);
    await underlyingOracle.mock.decimals.returns(8);

    blockTimestamp = await now(); // Tue Dec 28 2021 15:17:14 GMT+0000
  });

  revertToSnapshotAfterEach(async () => {});

  it('should initialize pool proxy', async () => {
    // strike interval: 100
    for (let isCall of [true, false]) {
      for (let strike of [
        parseEther('99900'),
        parseEther('1100'),
        parseEther('1000'),
        parseEther('900'),
        parseEther('100'),
      ]) {
        await p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        );
      }
    }
  });

  describe('should revert', () => {
    revertToSnapshotAfterEach(async () => {});
    it('if base == underlying || baseOracle == underlyingOracle', async () => {
      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          base.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__IdenticalAddresses',
        );
      }

      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          baseOracle.address,
          strike,
          maturity,
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__IdenticalAddresses',
        );
      }
    });

    it('if base == AddressZero || underlying == AddressZero', async () => {
      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          ethers.constants.AddressZero,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__ZeroAddress',
        );
      }

      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          underlying.address,
          ethers.constants.AddressZero,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__ZeroAddress',
        );
      }

      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          ethers.constants.AddressZero,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__ZeroAddress',
        );
      }

      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          ethers.constants.AddressZero,
          strike,
          maturity,
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__ZeroAddress',
        );
      }
    });

    it('if pool is already deployed', async () => {
      for (let isCall of [true, false]) {
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        );

        const tx = p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__PoolAlreadyDeployed',
        );
      }
    });

    it('if strike price is not within strike interval', async () => {
      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          0,
          maturity,
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__OptionStrikeEqualsZero',
        );
      }
    });

    it('if strike price is not within strike interval', async () => {
      // strike interval: 100
      for (let isCall of [true, false]) {
        for (let strike of [
          parseEther('99990'),
          parseEther('1050'),
          parseEther('950'),
          parseEther('11'),
        ]) {
          const tx = p.poolFactory.deployPool(
            base.address,
            underlying.address,
            baseOracle.address,
            underlyingOracle.address,
            strike,
            maturity,
            isCall,
          );
          await expect(tx).to.be.revertedWithCustomError(
            poolFactoryInterface,
            'PoolFactory__OptionStrikeInvalid',
          );
        }
      }
    });

    it('if daily option maturity has expired', async () => {
      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          blockTimestamp,
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__OptionExpired',
        );
      }
    });

    it('if daily option maturity is not at 8AM UTC', async () => {
      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          1640764801, // Wed Dec 29 2021 08:00:01 GMT+0000
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__OptionMaturityNot8UTC',
        );
      }
    });

    it('if weekly option maturity not on Friday', async () => {
      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          1641110400, // Sun Jan 02 2022 08:00:00 GMT+0000
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__OptionMaturityNotFriday',
        );
      }
    });

    it('if monthly option maturity not on last Friday', async () => {
      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          1645171200, // Fri Feb 18 2022 08:00:00 GMT+0000
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__OptionMaturityNotLastFriday',
        );
      }
    });

    it('if monthly option maturity exceeds 365 days', async () => {
      for (let isCall of [true, false]) {
        const tx = p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          1672387200, // Fri Dec 30 2022 08:00:00 GMT+0000
          isCall,
        );
        await expect(tx).to.be.revertedWithCustomError(
          poolFactoryInterface,
          'PoolFactory__OptionMaturityExceedsMax',
        );
      }
    });
  });
});
