![logo.JPG](logo.jpg)
---

`PoreMatMod.jl` is a [Julia](https://julialang.org/) package for (i) subgraph matching and (ii) modifying crystal structures such as metal-organic frameworks (MOFs).

Functioning as a "find-and-replace" tool on atomistic structure models of porous materials, `PoreMatMod.jl` is useful for:

:hammer: subgraph matching to filter databases of crystal structures

:hammer: create hypothetical crystal structure models of functionalized structures

:hammer: introduce defects into crystal structures

:hammer: repair artifacts of X-ray structure determination, such as missing hydrogen atoms, disorder, and guest molecules

N.b. while `PoreMatMod.jl` was developed for MOFs and other porous crystalline materials, its find-and-replace operations can be applied to discrete, molecular structures as well by assigning an arbitrary unit cell.

| **Documentation** | **Build Status** | 
|:---:|:---:|
| [![Docs Badge](https://img.shields.io/badge/docs-latest-blue.svg)](https://SimonEnsemble.github.io/PoreMatMod.jl/) | [![Build Status](https://travis-ci.org/SimonEnsemble/PoreMatMod.jl.svg?branch=master)](https://app.travis-ci.com/github/SimonEnsemble/PoreMatMod.jl) |


## Installation
`PoreMatMod.jl` is a registered Julia package and can be installed by entering the following line in the Julia REPL when in package mode (type `]` to enter package mode):

```
(v1.6) pkg> add PoreMatMod
```

## Documentation

Link to documentation [here](https://simonensemble.github.io/PoreMatMod.jl/).

## Gallery of examples

Link to examples [here](https://simonensemble.github.io/PoreMatMod.jl/examples/) with raw [Pluto](https://github.com/fonsp/Pluto.jl) notebooks [here](https://github.com/SimonEnsemble/PoreMatMod.jl/tree/master/examples).

## Citing
```latex
@misc{henle2021pmm,
    title={PoreMatMod.jl: Julia package for in silico post-synthetic modification of crystal structure models.},
    author={E. Adrian Henle and Nickolas Gantzler and Praveen K. Thallapally and Xiaoli Z. Fern and Cory M. Simon}
    year={2021}
    preprint={ChemRxiv}
}
```
## Contributing

`PoreMatMod.jl` is being actively developed and we encourage feature requests and community feedback [on GitHub](https://github.com/SimonEnsemble/PoreMatMod.jl/issues).

## License
`PoreMatMod.jl` is licensed under the [MIT license](./LICENSE).
