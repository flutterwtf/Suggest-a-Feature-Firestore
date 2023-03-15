import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:suggest_a_feature/suggest_a_feature.dart';

enum _Entity { suggestion, comment }

class FirestoreDataSource implements SuggestionsDataSource {
  static const String _suggestionIdFieldName = 'suggestion_id';
  static const String _authorIdFieldName = 'author_id';
  static const String _commentIdFieldName = 'comment_id';
  static const String _votedUsersArrayName = 'voted_user_ids';
  static const String _notificationsUsersArrayName = 'notify_user_ids';

  final String suggestionsCollectionPath;
  final String commentsCollectionPath;

  final FirebaseFirestore _firestoreInstance;

  @override
  final String userId;

  FirestoreDataSource({
    required this.userId,
    required FirebaseFirestore firestoreInstance,
    this.suggestionsCollectionPath = 'suggest_a_feature_suggestions',
    this.commentsCollectionPath = 'suggest_a_feature_comments',
  }) : _firestoreInstance = firestoreInstance;

  CollectionReference<Map<String, dynamic>> get _suggestions =>
      _firestoreInstance.collection(suggestionsCollectionPath);

  CollectionReference<Map<String, dynamic>> get _comments =>
      _firestoreInstance.collection(commentsCollectionPath);

  @override
  Future<Suggestion> getSuggestionById(String suggestionId) async {
    final DocumentSnapshot<Map<String, dynamic>> response =
        await _suggestions.doc(suggestionId).get();
    final Map<String, dynamic> rawSuggestionData =
        _addEntityId(_Entity.suggestion, response);
    return Suggestion.fromJson(json: rawSuggestionData);
  }

  @override
  Future<List<Suggestion>> getAllSuggestions() async {
    final QuerySnapshot<Map<String, dynamic>> response =
        await _suggestions.get();
    return response.docs.isNotEmpty
        ? response.docs.map<Suggestion>(
            (QueryDocumentSnapshot<Map<String, dynamic>> json) {
              final Map<String, dynamic> rawSuggestionData =
                  _addEntityId(_Entity.suggestion, json);
              return Suggestion.fromJson(json: rawSuggestionData);
            },
          ).toList()
        : <Suggestion>[];
  }

  @override
  Future<Suggestion> createSuggestion(CreateSuggestionModel suggestion) async {
    final DocumentReference<Map<String, dynamic>> reference =
        await _suggestions.add(suggestion.toJson());
    final DocumentSnapshot<Map<String, dynamic>> response =
        await _suggestions.doc(reference.id).get();
    return Suggestion.fromJson(
      json: _addEntityId(
        _Entity.suggestion,
        response,
      ),
    );
  }

  @override
  Future<Suggestion> updateSuggestion(Suggestion suggestion) async {
    if (!await _isUserAuthor(_Entity.suggestion, suggestion.id)) {
      throw Exception(
        'Failed to update the suggestion. User has no author rights',
      );
    }
    await _suggestions.doc(suggestion.id).update(suggestion.toUpdatingJson());
    return getSuggestionById(suggestion.id);
  }

  @override
  Future<void> deleteSuggestionById(String suggestionId) async {
    if (!await _isUserAuthor(_Entity.suggestion, suggestionId)) {
      throw Exception(
        'Failed to update the suggestion. User has no author rights',
      );
    }
    await _suggestions.doc(suggestionId).delete();
    await _commentsBatchDelete(suggestionId);
    return;
  }

  @override
  Future<List<Comment>> getAllComments(String suggestionId) async {
    final QuerySnapshot<Map<String, dynamic>> response = await _comments
        .where(_suggestionIdFieldName, isEqualTo: suggestionId)
        .get();
    return response.docs.isNotEmpty
        ? response.docs
            .map<Comment>(
              (QueryDocumentSnapshot<Map<String, dynamic>> json) =>
                  Comment.fromJson(json: _addEntityId(_Entity.comment, json)),
            )
            .toList()
        : <Comment>[];
  }

  @override
  Future<Comment> createComment(CreateCommentModel comment) async {
    final DocumentReference<Map<String, dynamic>> commentReference =
        await _comments.add(comment.toJson());
    return _getCommentById(commentReference.id);
  }

  @override
  Future<void> deleteCommentById(String commentId) async {
    if (!await _isUserAuthor(_Entity.comment, commentId)) {
      throw Exception(
        'Failed to update the suggestion. User has no author rights',
      );
    }
    return _comments.doc(commentId).delete();
  }

  Future<Comment> _getCommentById(String commentId) async {
    final DocumentSnapshot<Map<String, dynamic>> response =
        await _comments.doc(commentId).get();
    final Map<String, dynamic> rawData =
        _addEntityId(_Entity.comment, response);
    return Comment.fromJson(json: rawData);
  }

  Future<void> _commentsBatchDelete(String suggestionId) async {
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    final QuerySnapshot<Map<String, dynamic>> comments = await _comments
        .where(_suggestionIdFieldName, isEqualTo: suggestionId)
        .get();
    for (final QueryDocumentSnapshot<Map<String, dynamic>> document
        in comments.docs) {
      batch.delete(document.reference);
    }
    batch.commit();
  }

  @override
  Future<void> addNotifyToUpdateUser(String suggestionId) async {
    final List<String> userIdsToNotify =
        await _getSuggestionNotifications(suggestionId);
    if (userIdsToNotify.contains(userId)) {
      throw Exception(
        'Failed to add notification. User is already in notify list',
      );
    }
    return _suggestions.doc(suggestionId).update(<String, List<String>>{
      _notificationsUsersArrayName: <String>[...userIdsToNotify, userId]
    });
  }

  @override
  Future<void> deleteNotifyToUpdateUser(String suggestionId) async {
    final List<String> userIdsToNotify =
        await _getSuggestionNotifications(suggestionId);
    if (!userIdsToNotify.contains(userId)) {
      throw Exception(
        'Failed to remove notification. User is not in notify list',
      );
    }
    userIdsToNotify.remove(userId);
    return _suggestions.doc(suggestionId).update(
      <String, List<String>>{_notificationsUsersArrayName: userIdsToNotify},
    );
  }

  @override
  Future<void> upvote(String suggestionId) async {
    final List<String> votedUserIds = await _getSuggestionVotes(suggestionId);
    if (votedUserIds.contains(userId)) {
      throw Exception(
        'Failed to vote for the suggestion. User has already voted',
      );
    }
    return _suggestions.doc(suggestionId).update(<String, List<String>>{
      _votedUsersArrayName: <String>[...votedUserIds, userId]
    });
  }

  @override
  Future<void> downvote(String suggestionId) async {
    final List<String> votedUserIds = await _getSuggestionVotes(suggestionId);
    if (!votedUserIds.contains(userId)) {
      throw Exception(
        'Failed to remove the vote for the suggestion. '
        'User has not voted earlier',
      );
    }
    votedUserIds.remove(userId);
    return _suggestions
        .doc(suggestionId)
        .update(<String, List<String>>{_votedUsersArrayName: votedUserIds});
  }

  Future<List<String>> _getSuggestionVotes(String suggestionId) async {
    final DocumentSnapshot<Map<String, dynamic>> suggestionObject =
        await _suggestions.doc(suggestionId).get();
    final Map<String, dynamic> suggestion = suggestionObject.data()!;
    if (suggestion[_votedUsersArrayName] == null) {
      return <String>[];
    }
    return (suggestion[_votedUsersArrayName] as List<dynamic>).cast<String>();
  }

  Future<List<String>> _getSuggestionNotifications(String suggestionId) async {
    final DocumentSnapshot<Map<String, dynamic>> suggestionObject =
        await _suggestions.doc(suggestionId).get();
    final Map<String, dynamic> suggestion = suggestionObject.data()!;
    if (suggestion[_notificationsUsersArrayName] == null) {
      return <String>[];
    }
    return (suggestion[_notificationsUsersArrayName] as List<dynamic>)
        .cast<String>();
  }

  Future<bool> _isUserAuthor(_Entity entity, String entityId) async {
    final QuerySnapshot<Map<String, dynamic>> response;
    switch (entity) {
      case _Entity.suggestion:
        response = await _suggestions
            .where(_authorIdFieldName, isEqualTo: userId)
            .get();
        break;
      case _Entity.comment:
        response =
            await _comments.where(_authorIdFieldName, isEqualTo: userId).get();
        break;
    }
    final List<QueryDocumentSnapshot<Object?>> documents = response.docs
        .where((QueryDocumentSnapshot<Object?> e) => e.id == entityId)
        .toList();
    return documents.length == 1;
  }

  Map<String, dynamic> _addEntityId(
    _Entity entity,
    DocumentSnapshot<Map<String, dynamic>> item,
  ) {
    final Map<String, dynamic> rawData = item.data()!;
    switch (entity) {
      case _Entity.comment:
        rawData[_commentIdFieldName] = item.id;
        break;
      case _Entity.suggestion:
        rawData[_suggestionIdFieldName] = item.id;
        break;
    }
    return rawData;
  }
}
