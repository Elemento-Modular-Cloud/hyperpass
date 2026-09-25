(explanation-image)=
# Image

> See also: [`find`](/reference/command-line-interface/find), [`launch`](/reference/command-line-interface/launch)

Multipass uses **images** (short for [disk images](https://en.wikipedia.org/wiki/Disk_image) or [system images](https://en.wikipedia.org/wiki/System_image)) tuned for cloud usage to spin up VMs.

You can use `elp find` to view a list of the available images. These images are obtained from different sources, such as:
* Ubuntu Cloud Images: https://cloud-images.ubuntu.com/
* Ubuntu CD Images: https://cdimages.ubuntu.com/
* Third-party cloud images (Debian, Fedora, AlmaLinux, Rocky Linux, and others) catalogued by [Spacedock](https://spacedock.elemento.cloud) after Elemento Portal sign-in

and more.

You can also launch images from a file or URL, as long as they provide the tools required to deploy a cloud. The key requirements are:
* cloud-init
* SSH

## Custom third-party image catalog

Signed-in clients download the third-party image list from
[Spacedock](https://spacedock.elemento.cloud/v1/images/bundle) using the Portal
JWT. Guests, and any failed Spacedock fetch, keep **only Canonical Ubuntu**
images from `https://cloud-images.ubuntu.com/` (and the other Ubuntu remotes).

Point **elpd** at a local file or another URL with `ELP_DISTRIBUTIONS_URL`
(this wins over Spacedock). For a local Spacedock replica, set
`ELP_SPACEDOCK_URL` instead (for example `http://127.0.0.1:8080`). Headless
`elp find` can pass a JWT with `ELP_SPACEDOCK_TOKEN` when the GUI is not
syncing `local.spacedock.token`.

```text
# Local file (bare path)
ELP_DISTRIBUTIONS_URL=/absolute/path/to/distribution-info.json

# Local file (file URL)
ELP_DISTRIBUTIONS_URL=file:///absolute/path/to/distribution-info.json

# Remote catalog
ELP_DISTRIBUTIONS_URL=https://example.com/distribution-info.json
```

The daemon must be restarted after changing this variable. On macOS, add it to `/Library/LaunchDaemons/com.elemento.elpd.plist` (see [Configure where Multipass stores external data](how-to-guides-customise-multipass-configure-where-multipass-stores-external-data) for how to unload and reload that LaunchDaemon). Then run `elp find` and refresh the GUI catalogue.

For more information on the system requirements for a particular image, refer to official documentation (for example: [Ubuntu Core system requirements](https://ubuntu.com/core/docs/system-requirements)).
