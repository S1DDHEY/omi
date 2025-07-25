import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_provider_utilities/flutter_provider_utilities.dart';
import 'package:omi/backend/http/api/conversations.dart';
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/person.dart';
import 'package:omi/pages/capture/widgets/widgets.dart';
import 'package:omi/pages/conversation_detail/widgets.dart';
import 'package:omi/pages/home/page.dart';
import 'package:omi/providers/connectivity_provider.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/people_provider.dart';
import 'package:omi/utils/analytics/mixpanel.dart';
import 'package:omi/widgets/conversation_bottom_bar.dart';
import 'package:omi/widgets/expandable_text.dart';
import 'package:omi/widgets/extensions/string.dart';
import 'package:provider/provider.dart';
import 'package:tuple/tuple.dart';

import 'conversation_detail_provider.dart';
import 'widgets/name_speaker_sheet.dart';

class ConversationDetailPage extends StatefulWidget {
  final ServerConversation conversation;
  final bool isFromOnboarding;

  const ConversationDetailPage({super.key, this.isFromOnboarding = false, required this.conversation});

  @override
  State<ConversationDetailPage> createState() => _ConversationDetailPageState();
}

class _ConversationDetailPageState extends State<ConversationDetailPage> with TickerProviderStateMixin {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final focusTitleField = FocusNode();
  final focusOverviewField = FocusNode();
  TabController? _controller;
  ConversationTab selectedTab = ConversationTab.summary;

  // TODO: use later for onboarding transcript segment edits
  // late AnimationController _animationController;
  // late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _controller = TabController(length: 3, vsync: this, initialIndex: 1); // Start with summary tab
    _controller!.addListener(() {
      setState(() {
        switch (_controller!.index) {
          case 0:
            selectedTab = ConversationTab.transcript;
            break;
          case 1:
            selectedTab = ConversationTab.summary;
            break;
          case 2:
            selectedTab = ConversationTab.actionItems;
            break;
          default:
            debugPrint('Invalid tab index: ${_controller!.index}');
            selectedTab = ConversationTab.summary;
        }
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var provider = Provider.of<ConversationDetailProvider>(context, listen: false);
      await provider.initConversation();
      if (provider.conversation.appResults.isEmpty) {
        await Provider.of<ConversationProvider>(context, listen: false)
            .updateSearchedConvoDetails(provider.conversation.id, provider.selectedDate, provider.conversationIdx);
        provider.updateConversation(provider.conversationIdx, provider.selectedDate);
      }
    });
    // _animationController = AnimationController(
    //   vsync: this,
    //   duration: const Duration(seconds: 60),
    // )..repeat(reverse: true);
    //
    // _opacityAnimation = Tween<double>(begin: 1.0, end: 0.5).animate(_animationController);

    super.initState();
  }

  @override
  void dispose() {
    _controller?.dispose();
    focusTitleField.dispose();
    focusOverviewField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: MessageListener<ConversationDetailProvider>(
        showError: (error) {
          if (error == 'REPROCESS_FAILED') {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error while processing conversation. Please try again later.')));
          }
        },
        showInfo: (info) {},
        child: Scaffold(
          key: scaffoldKey,
          extendBody: true,
          backgroundColor: Theme.of(context).colorScheme.primary,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: Theme.of(context).colorScheme.primary,
            title: Consumer<ConversationDetailProvider>(builder: (context, provider, child) {
              return Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      if (widget.isFromOnboarding) {
                        SchedulerBinding.instance.addPostFrameCallback((_) {
                          Navigator.pushAndRemoveUntil(context,
                              MaterialPageRoute(builder: (context) => const HomePageWrapper()), (route) => false);
                        });
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 24.0),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (provider.titleController != null && provider.titleFocusNode != null) {
                          provider.titleFocusNode!.requestFocus();
                          // Select all text in the title field
                          provider.titleController!.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: provider.titleController!.text.length,
                          );
                        }
                      },
                      child: Text(
                        provider.structured.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await showModalBottomSheet(
                        context: context,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        builder: (context) {
                          return const ShowOptionsBottomSheet();
                        },
                      ).whenComplete(() {
                        provider.toggleShareOptionsInSheet(false);
                        provider.toggleDevToolsInSheet(false);
                      });
                    },
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              );
            }),
          ),
          // Removed floating action button as we now have the more button in the bottom bar
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Builder(builder: (context) {
                        return TabBarView(
                          controller: _controller,
                          physics: const NeverScrollableScrollPhysics(),
                          children: const [
                            TranscriptWidgets(),
                            SummaryTab(),
                            ActionItemsTab(),
                          ],
                        );
                      }),
                    ),
                  ),
                ],
              ),

              // Floating bottom bar
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Consumer<ConversationDetailProvider>(
                  builder: (context, provider, child) {
                    final conversation = provider.conversation;
                    return ConversationBottomBar(
                      mode: ConversationBottomBarMode.detail,
                      selectedTab: selectedTab,
                      hasSegments: conversation.transcriptSegments.isNotEmpty ||
                          conversation.photos.isNotEmpty ||
                          conversation.externalIntegration != null,
                      onTabSelected: (tab) {
                        int index;
                        switch (tab) {
                          case ConversationTab.transcript:
                            index = 0;
                            break;
                          case ConversationTab.summary:
                            index = 1;
                            break;
                          case ConversationTab.actionItems:
                            index = 2;
                            break;
                          default:
                            debugPrint('Invalid tab selected: $tab');
                            index = 1; // Default to summary tab
                        }
                        _controller!.animateTo(index);
                      },
                      onStopPressed: () {
                        // Empty since we don't show the stop button in detail mode
                      },
                    );
                  },
                ),
              ),

              // thinh's comment: temporary disabled
              //// Unassigned segments notification - positioned above the bottom bar
              //Positioned(
              //  bottom: 88, // Position above the bottom bar
              //  left: 16,
              //  right: 16,
              //  child: Selector<ConversationDetailProvider, ({bool shouldShow, int count})>(
              //    selector: (context, provider) {
              //      final conversation = provider.conversation;
              //      if (conversation == null) {
              //        return (
              //          count: 0,
              //          shouldShow: false,
              //        );
              //      }
              //      return (
              //        count: conversation.unassignedSegmentsLength(),
              //        shouldShow: provider.showUnassignedFloatingButton && (selectedTab == ConversationTab.transcript),
              //      );
              //    },
              //    builder: (context, value, child) {
              //      if (value.count == 0 || !value.shouldShow) return const SizedBox.shrink();
              //      return Container(
              //        padding: const EdgeInsets.symmetric(
              //          vertical: 8,
              //          horizontal: 16,
              //        ),
              //        decoration: BoxDecoration(
              //          borderRadius: BorderRadius.circular(16),
              //          color: Colors.grey.shade900,
              //          boxShadow: [
              //            BoxShadow(
              //              color: Colors.black.withOpacity(0.3),
              //              spreadRadius: 1,
              //              blurRadius: 2,
              //              offset: const Offset(0, 1),
              //            ),
              //          ],
              //        ),
              //        child: Row(
              //          mainAxisAlignment: MainAxisAlignment.spaceBetween,
              //          children: [
              //            Row(
              //              children: [
              //                InkWell(
              //                  onTap: () {
              //                    var provider = Provider.of<ConversationDetailProvider>(context, listen: false);
              //                    provider.setShowUnassignedFloatingButton(false);
              //                  },
              //                  child: const Icon(
              //                    Icons.close,
              //                    color: Colors.white,
              //                  ),
              //                ),
              //                const SizedBox(width: 8),
              //                Text(
              //                  "${value.count} unassigned segment${value.count == 1 ? '' : 's'}",
              //                  style: const TextStyle(
              //                    color: Colors.white,
              //                    fontSize: 16,
              //                  ),
              //                ),
              //              ],
              //            ),
              //            ElevatedButton(
              //              style: ElevatedButton.styleFrom(
              //                backgroundColor: Colors.deepPurple.withOpacity(0.5),
              //                shape: RoundedRectangleBorder(
              //                  borderRadius: BorderRadius.circular(16),
              //                ),
              //              ),
              //              onPressed: () {
              //                var provider = Provider.of<ConversationDetailProvider>(context, listen: false);
              //                var speakerId = provider.conversation.speakerWithMostUnassignedSegments();
              //                var segmentIdx = provider.conversation.firstSegmentIndexForSpeaker(speakerId);
              //                showModalBottomSheet(
              //                  context: context,
              //                  isScrollControlled: true,
              //                  backgroundColor: Colors.black,
              //                  shape: const RoundedRectangleBorder(
              //                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              //                  ),
              //                  builder: (context) {
              //                    return NameSpeakerBottomSheet(
              //                      segmentIdx: segmentIdx,
              //                      speakerId: speakerId,
              //                    );
              //                  },
              //                );
              //              },
              //              child: const Text(
              //                "Tag",
              //                style: TextStyle(
              //                  color: Colors.white,
              //                  fontWeight: FontWeight.bold,
              //                ),
              //              ),
              //            ),
              //          ],
              //        ),
              //      );
              //    },
              //  ),
              //),
            ],
          ),
        ),
      ),
    );
  }
}

class SummaryTab extends StatelessWidget {
  const SummaryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Selector<ConversationDetailProvider, Tuple3<bool, bool, Function(int)>>(
        selector: (context, provider) =>
            Tuple3(provider.conversation.discarded, provider.showRatingUI, provider.setConversationRating),
        builder: (context, data, child) {
          return Stack(
            children: [
              ListView(
                shrinkWrap: true,
                children: [
                  const GetSummaryWidgets(),
                  data.item1 ? const ReprocessDiscardedWidget() : const GetAppsWidgets(),
                  //const GetGeolocationWidgets(),
                  const SizedBox(height: 150)
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class TranscriptWidgets extends StatelessWidget {
  const TranscriptWidgets({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationDetailProvider>(
      builder: (context, provider, child) {
        final conversation = provider.conversation;
        final segments = conversation.transcriptSegments;
        final photos = conversation.photos;

        if (segments.isEmpty && photos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 32),
            child: ExpandableTextWidget(
              text: (provider.conversation.externalIntegration?.text ?? '').decodeString,
              maxLines: 1000,
              linkColor: Colors.grey.shade300,
              style: TextStyle(color: Colors.grey.shade300, fontSize: 15, height: 1.3),
              toggleExpand: () {
                provider.toggleIsTranscriptExpanded();
              },
              isExpanded: provider.isTranscriptExpanded,
            ),
          );
        }

        return getTranscriptWidget(
          false,
          segments,
          photos,
          null,
          horizontalMargin: false,
          topMargin: false,
          canDisplaySeconds: provider.canDisplaySeconds,
          isConversationDetail: true,
          bottomMargin: 150,
          editSegment: (segmentId, speakerId) {
            final connectivityProvider = Provider.of<ConnectivityProvider>(context, listen: false);
            if (!connectivityProvider.isConnected) {
              ConnectivityProvider.showNoInternetDialog(context);
              return;
            }
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.black,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (context) {
                return Consumer<PeopleProvider>(builder: (context, peopleProvider, child) {
                  return NameSpeakerBottomSheet(
                    speakerId: speakerId,
                    segmentId: segmentId,
                    segments: provider.conversation.transcriptSegments,
                    onSpeakerAssigned: (speakerId, personId, personName, segmentIds) async {
                      provider.toggleEditSegmentLoading(true);
                      String finalPersonId = personId;
                      if (personId.isEmpty) {
                        Person? newPerson = await peopleProvider.createPersonProvider(personName);
                        if (newPerson != null) {
                          finalPersonId = newPerson.id;
                        } else {
                          provider.toggleEditSegmentLoading(false);
                          return; // Failed to create person
                        }
                      }

                      MixpanelManager().taggedSegment(finalPersonId == 'user' ? 'User' : 'User Person');
                      for (final segmentId in segmentIds) {
                        final segmentIndex =
                            provider.conversation.transcriptSegments.indexWhere((s) => s.id == segmentId);
                        if (segmentIndex == -1) continue;
                        provider.conversation.transcriptSegments[segmentIndex].isUser = finalPersonId == 'user';
                        provider.conversation.transcriptSegments[segmentIndex].personId =
                            finalPersonId == 'user' ? null : finalPersonId;
                      }
                      await assignBulkConversationTranscriptSegments(
                        provider.conversation.id,
                        segmentIds,
                        isUser: finalPersonId == 'user',
                        personId: finalPersonId == 'user' ? null : finalPersonId,
                      );
                      provider.toggleEditSegmentLoading(false);
                    },
                  );
                });
              },
            );
          },
        );
      },
    );
  }
}

class ActionItemsTab extends StatelessWidget {
  const ActionItemsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Consumer<ConversationDetailProvider>(
        builder: (context, provider, child) {
          final hasActionItems = provider.conversation.structured.actionItems.where((item) => !item.deleted).isNotEmpty;

          return ListView(
            shrinkWrap: true,
            children: [
              const SizedBox(height: 24),
              if (hasActionItems) const ActionItemsListWidget() else _buildEmptyState(context),
              const SizedBox(height: 150)
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 72,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(
              'No Action Items',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'This memory doesn\'t have any action items yet. They\'ll appear here when your conversations include tasks or to-dos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
