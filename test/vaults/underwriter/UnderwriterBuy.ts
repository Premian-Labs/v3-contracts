import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  UnderwriterVaultMock,
  UnderwriterVaultMock__factory,
  UnderwriterVaultProxy__factory,
} from '../../../typechain';
import { PoolUtil } from '../../../utils/PoolUtil';

import { parseEther, parseUnits, formatEther } from 'ethers/lib/utils';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

describe('UnderwriterVault', () => {
  let deployer: SignerWithAddress;
  let caller: SignerWithAddress;
  let receiver: SignerWithAddress;
  let p: PoolUtil;
  let vault: UnderwriterVaultMock;

  let base: ERC20Mock;
  let quote: ERC20Mock;

  let baseOracle: MockContract;
  let volOracle: MockContract;

  const log = true;

  before(async () => {
    [deployer, caller, receiver] = await ethers.getSigners();

    base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    await base.deployed();
    await quote.deployed();

    await base.mint(caller.address, parseEther('1000'));
    await quote.mint(caller.address, parseEther('1000000'));

    await base.mint(receiver.address, parseEther('1000'));
    await quote.mint(receiver.address, parseEther('1000000'));

    await base.mint(deployer.address, parseEther('1000'));
    await quote.mint(deployer.address, parseEther('1000000'));

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.latestAnswer.returns(parseUnits('1', 8));
    await baseOracle.mock.decimals.returns(8);

    volOracle = await deployMockContract(deployer as any, [
      'function getVolatility(address, uint256, uint256, uint256) external view returns (int256)',
    ]);
    await volOracle.mock.getVolatility.returns(parseUnits('1'));

    p = await PoolUtil.deploy(
      deployer,
      base.address,
      baseOracle.address,
      deployer.address,
      parseEther('0.1'), // 10%
      true,
      true,
    );

    const vaultImpl = await new UnderwriterVaultMock__factory(deployer).deploy(
      volOracle.address,
      volOracle.address,
    );
    await vaultImpl.deployed();

    if (log)
      console.log(`UnderwriterVault Implementation : ${vaultImpl.address}`);

    const vaultProxy = await new UnderwriterVaultProxy__factory(
      deployer,
    ).deploy(
      vaultImpl.address,
      base.address,
      quote.address,
      baseOracle.address,
      'WETH Vault',
      'WETH',
      true,
    );
    await vaultProxy.deployed();

    vault = UnderwriterVaultMock__factory.connect(vaultProxy.address, deployer);

    if (log) console.log(`UnderwriterVaultProxy : ${vaultProxy.address}`);
  });

  describe('#setting up the environment', () => {
    it('', async () => {
      const assetAmount = parseEther('2');
      const shareAmount = await vault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });
  });

  describe('#buy', () => {
    it('test IV oracle mock', async () => {
      const iv = await volOracle.getVolatility(
        base.address,
        parseEther('2500'),
        parseEther('2000'),
        parseEther('0.2'),
      );
      expect(parseFloat(formatEther(iv))).to.eq(1);
    });
  });
});
