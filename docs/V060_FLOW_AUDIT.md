# v0.6.0 app flow audit

The app should let someone choose a meal change, see what the editor actually changed, and recover when a picture cannot be made. The review started at commit 79e699c and used an Android API 35 emulator, a Windows gateway, and an isolated spark02 worker.

| Priority | Finding | Fix and verification |
|---|---|---|
| 1 | The stock fish-soup photo was eligible for rice-based editing. Even a direct brown-rice request returned an image. | Restrict the automatic stock-photo path to the chicken and tofu rice references. Verified fish soup with added vegetables returns a summary in the APK and makes zero photo calls in the widget test. |
| 2 | Recolouring drove shaded rice nearly black even with a correct mask. | Raised the median target L* from 40 to 56 and reduced the contrast gain from 1.7 to 1.0. On 15 development photos with fixed masks, the median within-mask 10th-percentile L* rose from 22.3 to 43.7. All pixels outside every supplied mask were identical to the input. The Android chicken-rice result looked lighter and still received a failed checker verdict. |
| 3 | Choosing a gallery photo immediately sent a centre crop that the user had never seen. | Show the exact crop, change choices, and a send button. Verified on Android and tested that selecting the photo alone makes zero edit calls. |
| 4 | A temporary automatic edit failure discarded the photo. A combined edit could leave the user unable to correct just one change. | Return to review with the crop and error, allow a different change, and offer manual marking for single changes before sending. Tested a failed upload followed by a different edit using the same bytes. |
| 5 | Summary only could still call the image editor when both server capabilities were available. | Honour the selected summary path and restore the default mode on Clear. Tested the two-capability configuration with zero photo requests. |
| 6 | My Photo promised a healthier meal and Meals omitted the checker verdict. | Describe a visual preview and display the actual verdict with the meal picture. Verified the failed verdict appears alongside a saved chicken-rice picture in the installed APK. |
| 7 | The stock-photo cache could reuse an old tofu image or an older recolour, and a failed refresh silently showed the saved image. | Version the cache keys and label the fallback after a failed refresh. Verified saved-picture reuse after an Android restart and tested failed refresh with the earlier image still visible. |
| 8 | Navigating back during asynchronous cache access or image preparation could start an obsolete edit. Its completion could also stop a later progress indicator. | Check the active request after each preparation step and let the owning request stop its progress indicator. Reviewed cancellation paths and ran the Flutter suite. |
| 9 | iOS camera and photo-library purpose strings were missing. | Added both to Info.plist and verified the parsed values. iOS device permission prompts still need a device run. |
| 10 | The build gate accepted any nonempty catalogue JPEG, including the superseded tofu photo. | Reused the project's acquisition script with the current tofu hash and made the gate verify all three licensed files. Checked the assets used for this build. |

The tofu two-change request returned an image from both worker stages and failed the automatic check. General rice detection on arbitrary uploads, independent food realism assessment, and physical camera capture remain outside the verified results. The Android run used a gallery photo.
