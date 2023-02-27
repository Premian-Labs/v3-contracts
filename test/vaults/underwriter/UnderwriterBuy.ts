import { expect } from 'chai';
import { ethers } from 'hardhat';
import { getContractAddress } from 'ethers/lib/utils';
import {
  ERC20Mock,
  ERC20Mock__factory,
  UnderwriterVaultMock,
  UnderwriterVaultMock__factory,
  UnderwriterVaultProxy__factory,
  UnderwriterVaultProxy,
} from '../../../typechain';
import { PoolUtil } from '../../../utils/PoolUtil';
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
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

describe('UnderwriterVault', () => {
  let deployer: SignerWithAddress;
  let trader: SignerWithAddress;
  let lp: SignerWithAddress;

  let vaultImpl: UnderwriterVaultMock;
  let vaultProxy: UnderwriterVaultProxy;
  let vault: UnderwriterVaultMock;

  let base: ERC20Mock;
  let quote: ERC20Mock;

  let oracleAdapter: MockContract;
  let volOracle: MockContract;
  let factory: MockContract;

  const log = true;

  before(async () => {
    [deployer, trader, lp] = await ethers.getSigners();

    base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    await base.deployed();
    await quote.deployed();

    await base.mint(trader.address, parseEther('1000'));
    await quote.mint(trader.address, parseEther('1000000'));

    await base.mint(lp.address, parseEther('1000'));
    await quote.mint(lp.address, parseEther('1000000'));

    await base.mint(deployer.address, parseEther('1000'));
    await quote.mint(deployer.address, parseEther('1000000'));

    // Mock Oracle Adapter setup
    oracleAdapter = await deployMockContract(deployer, [
      'function quote(address, address) external view returns (uint256)',
    ]);

    await oracleAdapter.mock.quote.returns(parseUnits('1500', 8));

    if (log)
      console.log(
        `Mock oracelAdapter Implementation : ${oracleAdapter.address}`,
      );

    // Mock Vol Oracle setup
    volOracle = await deployMockContract(deployer, [
      'function getVolatility(address, uint256, uint256, uint256) external view returns (int256)',
    ]);
    await volOracle.mock.getVolatility.returns(parseUnits('1'));
    if (log)
      console.log(`Mock volOracle Implementation : ${volOracle.address}`);

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
    if (log) console.log(`Mock Pool Implementation : ${poolAddress}`);

    // Mock Vault setup
    vaultImpl = await new UnderwriterVaultMock__factory(deployer).deploy(
      volOracle.address,
      factory.address,
    );
    await vaultImpl.deployed();
    if (log)
      console.log(`UnderwriterVault Implementation : ${vaultImpl.address}`);

    // Vault Proxy setup
    vaultProxy = await new UnderwriterVaultProxy__factory(deployer).deploy(
      vaultImpl.address,
      base.address,
      quote.address,
      oracleAdapter.address,
      'WETH Vault',
      'WETH',
      true,
    );
    await vaultProxy.deployed();
    vault = UnderwriterVaultMock__factory.connect(vaultProxy.address, deployer);
    if (log) console.log(`UnderwriterVaultProxy : ${vaultProxy.address}`);
  });

  describe('#setting up the environment', () => {
    it('responds to basic function call', async () => {
      const assetAmount = parseEther('2');
      const shareAmount = await vault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });
  });

  describe('#buy functionality', () => {
    it('responds to mock IV oracle query', async () => {
      const iv = await volOracle.getVolatility(
        base.address,
        parseEther('2500'),
        parseEther('2000'),
        parseEther('0.2'),
      );
      expect(parseFloat(formatEther(iv))).to.eq(1);
    });
    it('responds to mock oracle adapter query', async () => {
      const price = await oracleAdapter.quote(base.address, quote.address);
      expect(parseFloat(formatUnits(price, 8))).to.eq(1500);
    });
  });
});
