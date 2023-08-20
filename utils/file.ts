import fs from 'fs';
import path from 'path';
import { ContractKey, ContractType } from './deployment/types';

export function getContractFilePaths(): string[] {
  let contractFilePaths: string[] = [];

  (function _getContractFilePaths(rootPath: string) {
    fs.readdirSync(rootPath).forEach((file) => {
      const absolutePath = path.join(rootPath, file);
      if (fs.statSync(absolutePath).isDirectory())
        return _getContractFilePaths(absolutePath);
      else return contractFilePaths.push(absolutePath);
    });
  })('./contracts');

  return contractFilePaths;
}

export function getContractFilePath(
  contractName: string,
  contractFilePaths: string[],
): string {
  for (const contractFilePath of contractFilePaths) {
    const contractFileNameWithExtension =
      contractFilePath.split('/').pop() ?? '';

    if (contractFileNameWithExtension.split('.')[0] === contractName)
      return contractFilePath;
  }

  return '';
}

export function throwIfContractFilePathNotFound(
  contractKey: ContractKey | string,
  contractType: ContractType,
) {
  if (contractKey in ContractKey) {
    const contractFilePaths = getContractFilePaths();
    const contractName = inferContractName(contractKey, contractType);
    const filePath = getContractFilePath(contractName, contractFilePaths);
    if (filePath === undefined || filePath.length === 0) {
      throw new Error(
        `Contract file path not found for ${contractKey} (${contractName})`,
      );
    }
  }
}

export function inferContractName(
  contractKey: string,
  contractType: ContractType | string,
) {
  const override = NameOverride[contractKey];
  if (override) return override;

  let name = addSpaceBetweenUpperCaseLetters(contractKey);
  // remove the contract type from the name, if it's there
  const typeInName = name.split(' ').pop() === contractType;

  if (typeInName) return name.split(' ').slice(0, -1).join('');
  return name.split(' ').join('');
}

export function inferContractDescription(
  contractKey: string,
  contractType: ContractType | string,
) {
  const override = DescriptionOverride[contractKey];
  if (override) return override;

  let name = addSpaceBetweenUpperCaseLetters(contractKey);
  // remove the contract type from the name, if it's there
  const typeInName = name.split(' ').pop() === contractType;

  if (typeInName) name = name.split(' ').slice(0, -1).join(' ');
  const type = addSpaceBetweenUpperCaseLetters(contractType);
  return `${name} ${type}`;
}

function addSpaceBetweenUpperCaseLetters(s: string) {
  return s.replace(/([a-z])([A-Z])/g, '$1 $2');
}

export const NameOverride: { [key: string]: string } = {
  PremiaDiamond: 'Premia',
  VxPremiaProxy: 'VxPremiaProxy',
  OptionPSImplementation: 'OptionPS',
  OptionPSFactoryImplementation: 'OptionPSFactory',
  ReferralProxy: 'ReferralProxy',
  VaultMiningProxy: 'VaultMiningProxy',
  PoolFactoryProxy: 'PoolFactoryProxy',
  OptionPSFactoryProxy: 'ProxyUpgradeableOwnable',
  ChainlinkAdapterProxy: 'ProxyUpgradeableOwnable',
  UserSettingsProxy: 'ProxyUpgradeableOwnable',
  VaultRegistryProxy: 'ProxyUpgradeableOwnable',
  VolatilityOracleProxy: 'ProxyUpgradeableOwnable',
  OptionRewardFactoryProxy: 'ProxyUpgradeableOwnable',
};

export const DescriptionOverride: { [key: string]: string } = {
  PremiaDiamond: 'Premia Diamond Proxy',
  VxPremiaImplementation: 'vxPREMIA Implementation',
  VxPremiaProxy: 'vxPREMIA Proxy',
  OptionPSImplementation: 'Option Physically Settled Implementation',
  OptionPSFactoryImplementation:
    'Option Physically Settled Factory Implementation',
  OptionPSFactoryProxy: 'Option Physically Settled Factory Proxy',
};
