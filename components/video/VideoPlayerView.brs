import "pkg:/source/utils/misc.brs"
import "pkg:/source/utils/config.brs"

sub init()
    ' Hide the overhang on init to prevent showing 2 clocks
    m.top.getScene().findNode("overhang").visible = false
    m.currentItem = m.global.queueManager.callFunc("getCurrentItem")

    m.top.id = m.currentItem.id
    m.top.seekMode = "accurate"

    m.playbackEnum = {
        null: -10
    }

    ' Load meta data
    m.LoadMetaDataTask = CreateObject("roSGNode", "LoadVideoContentTask")
    m.LoadMetaDataTask.itemId = m.currentItem.id
    m.LoadMetaDataTask.itemType = m.currentItem.type
    m.LoadMetaDataTask.selectedAudioStreamIndex = m.currentItem.selectedAudioStreamIndex
    m.LoadMetaDataTask.observeField("content", "onVideoContentLoaded")
    m.LoadMetaDataTask.control = "RUN"

    m.chapterList = m.top.findNode("chapterList")
    m.chapterMenu = m.top.findNode("chapterMenu")
    m.chapterContent = m.top.findNode("chapterContent")
    m.pauseMenu = m.top.findNode("pauseMenu")
    m.pauseMenu.observeField("action", "onPauseMenuAction")

    m.playbackTimer = m.top.findNode("playbackTimer")
    m.bufferCheckTimer = m.top.findNode("bufferCheckTimer")
    m.top.observeField("state", "onState")
    m.top.observeField("content", "onContentChange")
    m.top.observeField("selectedSubtitle", "onSubtitleChange")

    ' Custom Caption Function
    m.top.observeField("allowCaptions", "onAllowCaptionsChange")

    m.playbackTimer.observeField("fire", "ReportPlayback")
    m.bufferPercentage = 0 ' Track whether content is being loaded
    m.playReported = false
    m.top.transcodeReasons = []
    m.bufferCheckTimer.duration = 30

    if m.global.session.user.settings["ui.design.hideclock"] = true
        clockNode = findNodeBySubtype(m.top, "clock")
        if clockNode[0] <> invalid then clockNode[0].parent.removeChild(clockNode[0].node)
    end if

    'Play Next Episode button
    m.nextEpisodeButton = m.top.findNode("nextEpisode")
    m.nextEpisodeButton.text = tr("Next Episode")
    m.nextEpisodeButton.setFocus(false)

    m.showNextEpisodeButtonAnimation = m.top.findNode("showNextEpisodeButton")
    m.hideNextEpisodeButtonAnimation = m.top.findNode("hideNextEpisodeButton")

    m.checkedForNextEpisode = false
    m.getNextEpisodeTask = createObject("roSGNode", "GetNextEpisodeTask")
    m.getNextEpisodeTask.observeField("nextEpisodeData", "onNextEpisodeDataLoaded")

    m.top.retrievingBar.filledBarBlendColor = m.global.constants.colors.blue
    m.top.bufferingBar.filledBarBlendColor = m.global.constants.colors.blue
    m.top.trickPlayBar.filledBarBlendColor = m.global.constants.colors.blue
end sub

' handleChapterSkipAction: Handles user command to skip chapters in playing video
'
sub handleChapterSkipAction(action as string)
    if not isValidAndNotEmpty(m.chapters) then return

    currentChapter = getCurrentChapterIndex()

    if action = "chapternext"
        gotoChapter = currentChapter + 1
        ' If there is no next chapter, exit
        if gotoChapter > m.chapters.count() - 1 then return

        m.top.seek = m.chapters[gotoChapter].StartPositionTicks / 10000000#
        return
    end if

    if action = "chapterback"
        gotoChapter = currentChapter - 1
        ' If there is no previous chapter, restart current chapter
        if gotoChapter < 0 then gotoChapter = 0

        m.top.seek = m.chapters[gotoChapter].StartPositionTicks / 10000000#
        return
    end if
end sub

' handleHideAction: Handles action to hide pause menu
'
' @param {boolean} resume - controls whether or not to resume video playback when sub is called
'
sub handleHideAction(resume as boolean)
    m.pauseMenu.visible = false
    m.chapterList.visible = false
    m.pauseMenu.showChapterList = false
    m.chapterList.setFocus(false)
    m.pauseMenu.setFocus(false)
    m.top.setFocus(true)
    if resume
        m.top.control = "resume"
    end if
end sub

' handleChapterListAction: Handles action to show chapter list
'
sub handleChapterListAction()
    m.chapterList.visible = m.pauseMenu.showChapterList

    if not m.chapterList.visible then return

    m.chapterMenu.jumpToItem = getCurrentChapterIndex()

    m.pauseMenu.setFocus(false)
    m.chapterMenu.setFocus(true)
end sub

' getCurrentChapterIndex: Finds current chapter index
'
' @return {integer} indicating index of current chapter within chapter data or 0 if chapter lookup fails
'
function getCurrentChapterIndex() as integer
    if not isValidAndNotEmpty(m.chapters) then return 0

    ' Give a 15 second buffer to compensate for user expectation and roku video position inaccuracy
    ' Web client uses 10 seconds, but this wasn't enough for Roku in testing
    currentPosition = m.top.position + 15
    currentChapter = 0

    for i = m.chapters.count() - 1 to 0 step -1
        if currentPosition >= (m.chapters[i].StartPositionTicks / 10000000#)
            currentChapter = i
            exit for
        end if
    end for

    return currentChapter
end function

' handleVideoPlayPauseAction: Handles action to either play or pause the video content
'
sub handleVideoPlayPauseAction()
    ' If video is paused, resume it
    if m.top.state = "paused"
        m.top.control = "resume"
        return
    end if

    ' Pause video
    m.top.control = "pause"
end sub

' handleShowSubtitleMenuAction: Handles action to show subtitle selection menu
'
sub handleShowSubtitleMenuAction()
    m.top.selectSubtitlePressed = true
    handleHideAction(false)
end sub

' handleShowVideoInfoPopupAction: Handles action to show video info popup
'
sub handleShowVideoInfoPopupAction()
    m.top.selectPlaybackInfoPressed = true
    handleHideAction(false)
end sub

' onPauseMenuAction: Process action events from pause menu to their respective handlers
'
sub onPauseMenuAction()
    action = LCase(m.pauseMenu.action)

    if action = "hide"
        handleHideAction(false)
        return
    end if

    if action = "play"
        handleHideAction(true)
        return
    end if

    if action = "chapterback" or action = "chapternext"
        handleChapterSkipAction(action)
        return
    end if

    if action = "chapterlist"
        handleChapterListAction()
        return
    end if

    if action = "videoplaypause"
        handleVideoPlayPauseAction()
        return
    end if

    if action = "showsubtitlemenu"
        handleShowSubtitleMenuAction()
        return
    end if

    if action = "showvideoinfopopup"
        handleShowVideoInfoPopupAction()
        return
    end if
end sub

' Only setup caption items if captions are allowed
sub onAllowCaptionsChange()
    if not m.top.allowCaptions then return

    m.captionGroup = m.top.findNode("captionGroup")
    m.captionGroup.createchildren(9, "LayoutGroup")
    m.captionTask = createObject("roSGNode", "captionTask")
    m.captionTask.observeField("currentCaption", "updateCaption")
    m.captionTask.observeField("useThis", "checkCaptionMode")
    m.top.observeField("subtitleTrack", "loadCaption")
    m.top.observeField("globalCaptionMode", "toggleCaption")

    if m.global.session.user.settings["playback.subs.custom"]
        m.top.suppressCaptions = true
        toggleCaption()
    else
        m.top.suppressCaptions = false
    end if
end sub

' Set caption url to server subtitle track
sub loadCaption()
    if m.top.suppressCaptions
        m.captionTask.url = m.top.subtitleTrack
    end if
end sub

' Toggles visibility of custom subtitles and sets captionTask's player state
sub toggleCaption()
    m.captionTask.playerState = m.top.state + m.top.globalCaptionMode
    if LCase(m.top.globalCaptionMode) = "on"
        m.captionTask.playerState = m.top.state + m.top.globalCaptionMode + "w"
        m.captionGroup.visible = true
    else
        m.captionGroup.visible = false
    end if
end sub

' Removes old subtitle lines and adds new subtitle lines
sub updateCaption()
    m.captionGroup.removeChildrenIndex(m.captionGroup.getChildCount(), 0)
    m.captionGroup.appendChildren(m.captionTask.currentCaption)
end sub

' Event handler for when selectedSubtitle changes
sub onSubtitleChange()
    ' Save the current video position
    m.global.queueManager.callFunc("setTopStartingPoint", int(m.top.position) * 10000000&)

    m.top.control = "stop"

    m.LoadMetaDataTask.selectedSubtitleIndex = m.top.SelectedSubtitle
    m.LoadMetaDataTask.itemId = m.currentItem.id
    m.LoadMetaDataTask.observeField("content", "onVideoContentLoaded")
    m.LoadMetaDataTask.control = "RUN"
end sub

sub onPlaybackErrorDialogClosed(msg)
    sourceNode = msg.getRoSGNode()
    sourceNode.unobserveField("buttonSelected")
    sourceNode.unobserveField("wasClosed")

    m.global.sceneManager.callFunc("popScene")
end sub

sub onPlaybackErrorButtonSelected(msg)
    sourceNode = msg.getRoSGNode()
    sourceNode.close = true
end sub

sub showPlaybackErrorDialog(errorMessage as string)
    dialog = createObject("roSGNode", "Dialog")
    dialog.title = tr("Error During Playback")
    dialog.buttons = [tr("OK")]
    dialog.message = errorMessage
    dialog.observeField("buttonSelected", "onPlaybackErrorButtonSelected")
    dialog.observeField("wasClosed", "onPlaybackErrorDialogClosed")
    m.top.getScene().dialog = dialog
end sub

sub onVideoContentLoaded()
    m.LoadMetaDataTask.unobserveField("content")
    m.LoadMetaDataTask.control = "STOP"

    videoContent = m.LoadMetaDataTask.content
    m.LoadMetaDataTask.content = []

    ' If we have nothing to play, return to previous screen
    if not isValid(videoContent)
        showPlaybackErrorDialog(tr("There was an error retrieving the data for this item from the server."))
        return
    end if

    if not isValid(videoContent[0])
        showPlaybackErrorDialog(tr("There was an error retrieving the data for this item from the server."))
        return
    end if

    m.top.content = videoContent[0].content
    m.top.PlaySessionId = videoContent[0].PlaySessionId
    m.top.videoId = videoContent[0].id
    m.top.container = videoContent[0].container
    m.top.mediaSourceId = videoContent[0].mediaSourceId
    m.top.fullSubtitleData = videoContent[0].fullSubtitleData
    m.top.audioIndex = videoContent[0].audioIndex
    m.top.transcodeParams = videoContent[0].transcodeparams
    m.chapters = videoContent[0].chapters

    m.pauseMenu.itemTitleText = m.top.content.title

    populateChapterMenu()

    if m.LoadMetaDataTask.isIntro
        ' Disable trackplay bar for intro videos
        m.top.enableTrickPlay = false
    else
        ' Allow custom captions for non intro videos
        m.top.allowCaptions = true
    end if

    if isValid(m.top.audioIndex)
        m.top.audioTrack = (m.top.audioIndex + 1).toStr()
    else
        m.top.audioTrack = "2"
    end if

    m.top.setFocus(true)
    m.top.control = "play"
end sub

' populateChapterMenu: ' Parse chapter data from API and appeand to chapter list menu
'
sub populateChapterMenu()
    ' Clear any existing chapter list data
    m.chapterContent.clear()

    if not isValidAndNotEmpty(m.chapters)
        chapterItem = CreateObject("roSGNode", "ContentNode")
        chapterItem.title = tr("No Chapter Data Found")
        chapterItem.playstart = m.playbackEnum.null
        m.chapterContent.appendChild(chapterItem)
        return
    end if

    for each chapter in m.chapters
        chapterItem = CreateObject("roSGNode", "ContentNode")
        chapterItem.title = chapter.Name
        chapterItem.playstart = chapter.StartPositionTicks / 10000000#
        m.chapterContent.appendChild(chapterItem)
    end for
end sub

' Event handler for when video content field changes
sub onContentChange()
    if not isValid(m.top.content) then return

    m.top.observeField("position", "onPositionChanged")
end sub

sub onNextEpisodeDataLoaded()
    m.checkedForNextEpisode = true

    m.top.observeField("position", "onPositionChanged")
end sub

'
' Runs Next Episode button animation and sets focus to button
sub showNextEpisodeButton()
    if m.global.session.user.configuration.EnableNextEpisodeAutoPlay and not m.nextEpisodeButton.visible
        m.showNextEpisodeButtonAnimation.control = "start"
        m.nextEpisodeButton.setFocus(true)
        m.nextEpisodeButton.visible = true
    end if
end sub

'
'Update count down text
sub updateCount()
    m.nextEpisodeButton.text = tr("Next Episode") + " " + Int(m.top.duration - m.top.position).toStr()
end sub

'
' Runs hide Next Episode button animation and sets focus back to video
sub hideNextEpisodeButton()
    m.hideNextEpisodeButtonAnimation.control = "start"
    m.nextEpisodeButton.setFocus(false)
    m.top.setFocus(true)
end sub

' Checks if we need to display the Next Episode button
sub checkTimeToDisplayNextEpisode()
    if int(m.top.position) >= (m.top.duration - 30)
        showNextEpisodeButton()
        updateCount()
        return
    end if

    if m.nextEpisodeButton.visible or m.nextEpisodeButton.hasFocus()
        m.nextEpisodeButton.visible = false
        m.nextEpisodeButton.setFocus(false)
    end if
end sub

' When Video Player state changes
sub onPositionChanged()
    if isValid(m.captionTask)
        m.captionTask.currentPos = Int(m.top.position * 1000)
    end if

    ' Check if dialog is open
    m.dialog = m.top.getScene().findNode("dialogBackground")
    if not isValid(m.dialog)
        ' Do not show Next Episode button for intro videos
        if not m.LoadMetaDataTask.isIntro
            checkTimeToDisplayNextEpisode()
        end if
    end if
end sub

'
' When Video Player state changes
sub onState(msg)
    if isValid(m.captionTask)
        m.captionTask.playerState = m.top.state + m.top.globalCaptionMode
    end if

    ' Pass video state into pause menu
    m.pauseMenu.playbackState = m.top.state

    ' When buffering, start timer to monitor buffering process
    if m.top.state = "buffering" and m.bufferCheckTimer <> invalid

        ' start timer
        m.bufferCheckTimer.control = "start"
        m.bufferCheckTimer.ObserveField("fire", "bufferCheck")
    else if m.top.state = "error"
        if not m.playReported and m.top.transcodeAvailable
            m.top.retryWithTranscoding = true ' If playback was not reported, retry with transcoding
        else
            ' If an error was encountered, Display dialog
            showPlaybackErrorDialog(tr("Error During Playback"))
        end if

        ' Stop playback and exit player
        m.top.control = "stop"
        m.top.backPressed = true
    else if m.top.state = "playing"

        ' Check if next episde is available
        if isValid(m.top.showID)
            if m.top.showID <> "" and not m.checkedForNextEpisode and m.top.content.contenttype = 4
                m.getNextEpisodeTask.showID = m.top.showID
                m.getNextEpisodeTask.videoID = m.top.id
                m.getNextEpisodeTask.control = "RUN"
            end if
        end if

        if m.playReported = false
            ReportPlayback("start")
            m.playReported = true
        else
            ReportPlayback()
        end if
        m.playbackTimer.control = "start"
    else if m.top.state = "paused"
        m.playbackTimer.control = "stop"
        ReportPlayback()
    else if m.top.state = "stopped"
        m.playbackTimer.control = "stop"
        ReportPlayback("stop")
        m.playReported = false
    end if

end sub

'
' Report playback to server
sub ReportPlayback(state = "update" as string)

    if m.top.position = invalid then return

    params = {
        "ItemId": m.top.id,
        "PlaySessionId": m.top.PlaySessionId,
        "PositionTicks": int(m.top.position) * 10000000&, 'Ensure a LongInteger is used
        "IsPaused": (m.top.state = "paused")
    }
    if m.top.content.live
        params.append({
            "MediaSourceId": m.top.transcodeParams.MediaSourceId,
            "LiveStreamId": m.top.transcodeParams.LiveStreamId
        })
        m.bufferCheckTimer.duration = 30
    end if

    ' Report playstate via worker task
    playstateTask = m.global.playstateTask
    playstateTask.setFields({ status: state, params: params })
    playstateTask.control = "RUN"
end sub

'
' Check the the buffering has not hung
sub bufferCheck(msg)

    if m.top.state <> "buffering"
        ' If video is not buffering, stop timer
        m.bufferCheckTimer.control = "stop"
        m.bufferCheckTimer.unobserveField("fire")
        return
    end if
    if m.top.bufferingStatus <> invalid

        ' Check that the buffering percentage is increasing
        if m.top.bufferingStatus["percentage"] > m.bufferPercentage
            m.bufferPercentage = m.top.bufferingStatus["percentage"]
        else if m.top.content.live = true
            m.top.callFunc("refresh")
        else
            ' If buffering has stopped Display dialog
            showPlaybackErrorDialog(tr("There was an error retrieving the data for this item from the server."))

            ' Stop playback and exit player
            m.top.control = "stop"
            m.top.backPressed = true
        end if
    end if

end sub

function onKeyEvent(key as string, press as boolean) as boolean

    ' Keypress handler while user is inside the chapter menu
    if m.chapterMenu.hasFocus()
        if not press then return false

        if key = "OK"
            focusedChapter = m.chapterMenu.itemFocused
            selectedChapter = m.chapterMenu.content.getChild(focusedChapter)
            seekTime = selectedChapter.playstart

            ' Don't seek if user clicked on No Chapter Data
            if seekTime = m.playbackEnum.null then return true

            m.top.seek = seekTime
            return true
        end if

        if key = "back" or key = "replay"
            m.chapterList.visible = false
            m.pauseMenu.showChapterList = false
            m.chapterMenu.setFocus(false)
            m.pauseMenu.setFocus(true)
            return true
        end if

        if key = "play"
            handleVideoPlayPauseAction()
        end if

        return true
    end if

    if key = "OK" and m.nextEpisodeButton.hasfocus() and not m.top.trickPlayBar.visible
        m.top.control = "stop"
        m.top.state = "finished"
        hideNextEpisodeButton()
        return true
    else
        'Hide Next Episode Button
        if m.nextEpisodeButton.visible or m.nextEpisodeButton.hasFocus()
            m.nextEpisodeButton.visible = false
            m.nextEpisodeButton.setFocus(false)
            m.top.setFocus(true)
        end if
    end if

    if not press then return false

    if key = "down"
        if m.pauseMenu.visible then return true

        ' Do not show subtitle selection for intro videos
        if not m.LoadMetaDataTask.isIntro
            m.top.selectSubtitlePressed = true
            return true
        end if

    else if key = "up"
        ' Do not show playback info for intro videos
        if not m.LoadMetaDataTask.isIntro
            m.top.selectPlaybackInfoPressed = true
            return true
        end if

    else if key = "OK" and not m.top.trickPlayBar.visible
        if not m.LoadMetaDataTask.isIntro
            ' Show pause menu, but don't pause video
            m.pauseMenu.visible = true
            m.pauseMenu.setFocus(true)
            return true
        end if

        return false
    end if

    ' Disable pause menu for intro videos
    if not m.LoadMetaDataTask.isIntro
        if key = "play" and not m.top.trickPlayBar.visible
            ' If video is paused, resume it and don't show pause menu
            if m.top.state = "paused"
                m.top.control = "resume"
                return true
            end if

            ' Pause video and show pause menu
            m.top.control = "pause"
            m.pauseMenu.visible = true
            m.pauseMenu.setFocus(true)
            return true
        end if
    end if

    if key = "back"
        m.top.control = "stop"
    end if

    return false
end function
