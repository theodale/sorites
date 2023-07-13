# Sorites Core

Core smart contracts for the Sorites Protocol.

## Development Conventions

### Github Flow

- Open an issue for task
- Create branch with `dev-name/issue-number/task` e.g. `pete/1/lido-pool`
- Use all lowercase
- Make a PR to main when task is done
- Requires one review before merge
- TODO: github actions

### Solidity Style

- Import explicity: `import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";`
- Function parameters prefixed with an underscore: `function deposit(uint256 _amount)`
- Each contract has an interface it inherits that contains:
  - Virtual functions that can be overriden for each function in the base contract
  - Events
  - Custom Errors
- Such interfaces should be named as `IContractName`
- Put spacing between blocks of logicially similar content
- Be generous and explicity with comments
- Internal functions should be prefixed with an underscore: `function _myInternalMethod()`

### Test Convention

- Start one test file per contract
