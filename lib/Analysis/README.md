Back-End

## Reference:
https://github.com/MikePopoloski/slang/blob/master/source/analysis
-> source/analysis/DataFlowAnalysis.cpp → Connectivity issues source/analysis/DriverTracker.cpp → Driver conflicts 
-> source/analysis/ClockInference.cpp → Clock domain problems

## Dataflow Analysis:
Dataflow Analysis Errors: Undriven signals, multiple drivers, driver conflicts
Procedural Analysis Errors: Invalid always/initial block constructs
Control Flow Errors: Unreachable code, invalid case statements
Clock Domain Errors: Clock crossing violations, invalid clock inference
Connectivity Errors: Unconnected ports, width mismatches
Static Assertion Failures: Compile-time assertion violations
Optimization Errors: Invalid transformations, optimization failures
Code Generation Errors: Invalid target code, resource allocation failures
