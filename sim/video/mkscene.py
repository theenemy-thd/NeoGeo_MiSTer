#!/usr/bin/env python3
import sys; sys.path.insert(0, __file__.rsplit("/", 1)[0])
import recipes
getattr(recipes, sys.argv[1])(int(sys.argv[2])).write(sys.argv[3])
