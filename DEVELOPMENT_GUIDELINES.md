# Development Guidelines

## Code Quality Principles

### 1. Clean Code
- **Remove obsolete code**: When fixing or removing a feature, delete all related code
- **No dead code**: Don't leave commented-out code or unused functions
- **Single responsibility**: Each function/class should do one thing well
- **Clear naming**: Use descriptive names that explain intent

### 2. Incremental Development
- **One feature at a time**: Implement and test each feature completely before moving to the next
- **Small commits**: Make focused commits for each feature or fix
- **Test as you go**: Verify each feature works before adding the next

### 3. Code Organization
- **Follow folder structure**: Keep files in their designated folders
- **Consistent patterns**: Use consistent coding patterns across the codebase
- **Documentation**: Comment complex logic, keep README files updated

## Feature Implementation Workflow

1. **Plan**: Review technical plan, understand requirements
2. **Implement**: Write clean, focused code
3. **Test**: Verify the feature works correctly
4. **Clean**: Remove any temporary/debug code
5. **Document**: Update relevant documentation
6. **Commit**: Make a focused commit with clear message

## Code Review Checklist

Before committing:
- [ ] Code follows project structure
- [ ] No dead/commented code
- [ ] Functions are focused and clear
- [ ] Error handling is appropriate
- [ ] No hardcoded values (use config/env)
- [ ] Code is tested and working

## Removing Features

When removing a feature:
1. Remove all related code (scripts, UI, data)
2. Remove database migrations/tables if applicable
3. Update documentation
4. Clean up any references in other files
5. Test that nothing breaks

## Adding Features

When adding a feature:
1. Create feature branch (if using Git flow)
2. Implement feature incrementally
3. Test thoroughly
4. Clean up any temporary code
5. Update documentation
6. Merge to main

## Testing Strategy

- **Unit tests**: Test individual functions/components
- **Integration tests**: Test feature interactions
- **Manual testing**: Test in game/client before considering complete
- **Edge cases**: Consider error cases and boundary conditions

