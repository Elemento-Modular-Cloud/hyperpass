(explanation-image)=
# Image

> See also: [`find`](/reference/command-line-interface/find), [`launch`](/reference/command-line-interface/launch)

Multipass uses **images** (short for [disk images](https://en.wikipedia.org/wiki/Disk_image) or [system images](https://en.wikipedia.org/wiki/System_image)) tuned for cloud usage to spin up VMs.

You can use `multipass find` to view a list of the available images. These images are obtained from different sources, such as:
* Ubuntu Cloud Images: https://cloud-images.ubuntu.com/
* Ubuntu CD Images: https://cdimages.ubuntu.com/
* Third-party cloud images (Debian, Fedora, AlmaLinux, Rocky Linux) catalogued in the [distribution manifest](https://github.com/canonical/multipass/blob/main/data/distributions/distribution-info.json)

and more.

You can also launch images from a file or URL, as long as they provide the tools required to deploy a cloud. The key requirements are:
* cloud-init
* SSH

## Custom third-party image catalog

By default, Multipass downloads the third-party image list from GitHub. To use a different catalog — a local file or another URL — set `MULTIPASS_DISTRIBUTIONS_URL` on the Multipass daemon:

```text
# Local file (bare path)
MULTIPASS_DISTRIBUTIONS_URL=/absolute/path/to/distribution-info.json

# Local file (file URL)
MULTIPASS_DISTRIBUTIONS_URL=file:///absolute/path/to/distribution-info.json

# Remote catalog
MULTIPASS_DISTRIBUTIONS_URL=https://example.com/distribution-info.json
```

The daemon must be restarted after changing this variable. On macOS, add it to `/Library/LaunchDaemons/com.canonical.multipassd.plist` (see [Configure where Multipass stores external data](how-to-guides-customise-multipass-configure-where-multipass-stores-external-data) for how to unload and reload that LaunchDaemon). Then run `multipass find` and refresh the GUI catalogue.

For more information on the system requirements for a particular image, refer to official documentation (for example: [Ubuntu Core system requirements](https://ubuntu.com/core/docs/system-requirements)).
