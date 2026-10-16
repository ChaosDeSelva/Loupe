-- Compatibility entry point for source examples and standalone simulation tests.
package.path = "../../?.lua;../../?/init.lua;" .. package.path
return require("loupe.collision")
