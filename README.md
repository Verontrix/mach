<a href="https://machengine.org">
    <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://machengine.org/assets/media/mach/logo_dark.svg">
        <img alt="mach-opus" src="https://machengine.org/assets/media/mach/logo_light.svg" height="100px">
    </picture>
</a>

Zig game engine & graphics toolkit for building high-performance, truly cross-platform, robust & modular games, visualizations, and desktop/mobile GUI apps.

<a href="https://user-images.githubusercontent.com/3173176/173177664-2ac9e90b-9429-4b09-aaf9-b80b53fee49f.gif"><img align="left" src="https://user-images.githubusercontent.com/3173176/173177664-2ac9e90b-9429-4b09-aaf9-b80b53fee49f.gif" alt="gen-texture-light" height="190px"></img></a>
<a href="https://user-images.githubusercontent.com/3173176/163936001-fd9eb918-7c29-4dcc-bfcb-5586f2ea1f9a.gif"><img align="left" src="https://user-images.githubusercontent.com/3173176/163936001-fd9eb918-7c29-4dcc-bfcb-5586f2ea1f9a.gif" alt="boids" height="190px"></img></a>
<a href="https://user-images.githubusercontent.com/3173176/173177646-a3f0982c-f07b-496f-947b-265bdc71ece9.gif"><img src="https://user-images.githubusercontent.com/3173176/173177646-a3f0982c-f07b-496f-947b-265bdc71ece9.gif" alt="textured-cube" height="190px"></img></a>

## Learn more

See [machengine.org](https://machengine.org) for docs, tutorials, etc.

## Development

Development occurs on [code.hexops.org](https://code.hexops.org/hexops/mach) - our GitHub [mirror](https://github.com/hexops/mach) is purely for visibility.

### What the Fork?
One of the challenges that when using Mach alongside other Zig packages is version compatibility. Many Zig libraries target Zig's official releases or master, while Mach has historically relied on its own nominated Zig versions. As a result, combining Mach with other libraries doesn't work, unless you spend a lot of time modifying those packages to be compatibile with the Mach nominated version. This is a bad decision and holds back many people from using Mach.

This fork aims to address that issue by targeting official Zig releases rather than Mach-nominated Zig versions. The goal is to make Mach easier to use alongside the wider Zig ecosystem, simplify dependency management, and enable developers to build cross-platform applications and games using the Zig version they already use for their other projects.

## Join the community

Join the [Mach community on Discord](https://discord.gg/XNG3NZgCqp) to discuss this project, ask questions, get help, etc.

**We're here to make games in Zig and have fun, so please help us keep the community focused on that.** Everyone is welcome here, LGBTQ+ and otherwise. 💛
