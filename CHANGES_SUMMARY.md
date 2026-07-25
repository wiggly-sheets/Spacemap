## Changes Made
- Added refreshWorkItem and isFetching properties
- Rewrote show() to show empty panel first, fetch data in background
- Added fetchStateAndRender() and renderEmptyState() helper methods
- Rewrote startPollTimer() to dispatch query off main thread
- Rewrote refreshState() with debounce using refreshWorkItem
- Updated hide() to cancel work item

## Philosophy Compliance
- Early Exit: Guard clauses handle edge cases at top of functions
- Parse Don't Validate: Data is parsed on background thread, trusted on main thread
- Atomic Predictability: Functions are predictable with clear inputs/outputs
- Fail Fast: Invalid states are handled with early returns and clear logging
- Intentional Naming: Function and variable names clearly describe their purpose

## Verification
- Build: SUCCESS
- Tests: 131 passed, 0 failed
- All requested changes implemented correctly
