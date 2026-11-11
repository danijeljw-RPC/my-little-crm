import 'package:flutter/material.dart';

import '../../domain/models.dart';

extension CommunicationMethodIcon on CommunicationMethod {
  IconData get icon => switch (this) {
    CommunicationMethod.phone => Icons.phone_outlined,
    CommunicationMethod.email => Icons.email_outlined,
    CommunicationMethod.sms => Icons.sms_outlined,
    CommunicationMethod.letter => Icons.markunread_mailbox_outlined,
    CommunicationMethod.chat => Icons.chat_bubble_outline,
    CommunicationMethod.other => Icons.more_horiz,
  };
}
