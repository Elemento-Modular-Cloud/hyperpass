if(MULTIPASS_ENABLE_FLUTTER_GUI)
  install(
    FILES elp.gui.desktop
    DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
  )
endif()

install(
  FILES elp.gui.svg
  DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps
)
