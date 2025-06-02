# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Steep is a gradual type checker for Ruby that requires explicit type declarations using RBS (Ruby Signature) files. It performs static type checking without type inference and integrates with editors via Language Server Protocol.

## Common Development Commands

### Running Tests
```bash
# Run all unit tests
rake test

# Run smoke tests (integration tests with expected diagnostics)
rake test:output

# Run a specific test file
ruby -Itest test/type_check_test.rb

# Run current smoke test in a directory
cd smoke/alias && rake test:output:current
```

### Type Checking
```bash
# Type check the Steep codebase itself
steep check

# Type check with specific severity
steep check --severity=error

# Watch mode for continuous type checking
steep watch

# Start language server
steep langserver
```

### Building and Development
```bash
# Initial setup
bin/setup

# Generate RBS signatures from test files using rbs-inline
rake rbs:generate

# Watch and regenerate RBS signatures
rake rbs:watch

# Install gem locally
bundle exec rake install

# Build gem
bundle exec rake build
```

## Architecture Overview

### Core Type Checking Flow
1. **Parser Phase**: Ruby code is parsed into AST using the parser gem
2. **Type Construction**: `TypeConstruction` class builds typed AST by:
   - Reading RBS signatures from sig/ directories
   - Processing annotations (@type, @dynamic, etc.)
   - Building type environments
3. **Subtyping Check**: `Subtyping::Check` validates type relationships
4. **Diagnostics**: Type errors are collected and formatted

### Key Components

**Type System Core** (`lib/steep/`):
- `type_construction.rb`: Main type checking logic that traverses AST
- `type_inference/`: Components for inferring types in specific contexts
- `subtyping/`: Subtyping relationship validation
- `interface/`: Type interface definitions and method resolution

**Language Server** (`lib/steep/server/`):
- `master.rb`: Coordinates worker processes
- `type_check_worker.rb`: Performs type checking in background
- `interaction_worker.rb`: Handles completion, hover, goto definition

**Services** (`lib/steep/services/`):
- `type_check_service.rb`: Manages incremental type checking
- `signature_service.rb`: Manages RBS signatures and dependencies
- `completion_provider.rb`: Provides code completion

### Testing Strategy

1. **Unit Tests**: Traditional tests in `test/` directory
2. **Smoke Tests**: Integration tests in `smoke/` with:
   - Each test case in its own directory
   - `test_expectations.yml` defines expected diagnostics
   - Tests cover Ruby features and edge cases

### Configuration

**Steepfile**: Defines type checking targets
- `check`: Directories to type check
- `signature`: RBS signature directories  
- `library`: Standard library dependencies
- `collection_config`: External RBS definitions
- Multiple targets supported (app, test, bin)

**RBS Collection**: Manages external type definitions via `rbs_collection.steep.yaml`

## Key Implementation Details

- Self-hosted: Steep type-checks its own codebase
- Uses RBS 4.0.0.dev (development version)
- Requires Ruby 3.1.0+
- Diagnostic severity levels: error, warning, information, hint
- Supports gradual typing with @dynamic annotations
- Implements LSP for IDE integration