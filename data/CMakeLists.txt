if(MULTIPASS_ENABLE_FLUTTER_GUI)
  install(
    FILES hyperpass.gui.desktop
    DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
  )
endif()

install(
  FILES hyperpass.gui.svg
  DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps
)
