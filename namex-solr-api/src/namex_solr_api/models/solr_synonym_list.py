# Copyright © 2025 Province of British Columbia
#
# Licensed under the BSD 3 Clause License, (the "License");
# you may not use this file except in compliance with the License.
# The template for the license can be found here
#    https://opensource.org/license/bsd-3-clause/
#
# Redistribution and use in source and binary forms,
# with or without modification, are permitted provided that the
# following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS”
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
"""Manages solr synonym lists (used for prepping solr queries over synonym fields)."""
from __future__ import annotations

from datetime import UTC, datetime
from enum import auto

from sqlalchemy import Column, DateTime, String, func
from sqlalchemy.dialects.postgresql import JSONB, insert
from sqlalchemy.orm import Mapped, mapped_column

from namex_solr_api.common.base_enum import BaseEnum

from .base import Base
from .db import db


class SolrSynonymList(Base):
    """Used to hold solr synonym information."""
    
    class Type(BaseEnum):
        """Enum of the solr synonym types."""

        ALL = auto()

    __tablename__ = "solr_synonym_lists"

    id: Mapped[int] = mapped_column(primary_key=True)
    synonym: Mapped[str] = mapped_column(String(50), index=True)
    synonym_list = Column(JSONB, nullable=False)
    synonym_type: Mapped[Type] = mapped_column(default=Type.ALL.value, index=True)
    last_update_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=func.now())

    @classmethod
    def find_by_synonym(cls, synonym: str, synonym_type: Type) -> SolrSynonymList:
        """Return all the solr synonym objects for synonyms including the given phrase/word."""
        return cls.query.filter_by(synonym=synonym.lower(), synonym_type=synonym_type.value).one_or_none()

    @classmethod
    def find_all_by_synonyms(cls, synonyms: list[str], synonym_type: Type) -> list[SolrSynonymList]:
        """Return all the solr synonym objects for the given list and type."""
        return cls.query.filter_by(synonym_type=synonym_type.value).filter(cls.synonym.in_(synonyms)).all()
    
    @classmethod
    def find_all_excluding(cls, synonyms: list[str], synonym_type: Type) -> list[SolrSynonymList]:
        """Return all the solr synonym objects not in the given list for the type."""
        return cls.query.filter_by(synonym_type=synonym_type.value).filter(cls.synonym.notin_(synonyms)).all()
    
    @classmethod
    def find_all_by_synonym_type(cls, synonym_type: Type) -> list[SolrSynonymList]:
        """Return all the solr synonym objects for the type."""
        return cls.query.filter_by(synonym_type=synonym_type.value).all()

    @classmethod
    def find_all_beginning_with_phrase(cls, phrase: str, synonym_type: Type) -> list[SolrSynonymList]:
        """Return all the solr synonym objects for synonyms including the given phrase/word."""
        return cls.query.filter_by(synonym_type=synonym_type.value).filter(cls.synonym.ilike(f"{phrase}%")).all()
    
    @staticmethod
    def create_or_replace(synonym_type: SolrSynonymList.Type, synonym: str, synonym_list: list[str], replace: bool):
        """Create, Add to, or replace the given synonym inside the db."""
        # NOTE: References to empty synonyms in solr will break the synonym filters
        if not synonym or not synonym.strip():
            # Ignore references to empty strings etc.
            return
        # Filter out any empty strings etc.
        synonym_list = [syn.strip() for syn in synonym_list if syn]
        if synonym in synonym_list:
            # remove any reference to itself
            synonym_list.remove(synonym)
        if synonym_list_record := SolrSynonymList.find_by_synonym(synonym, synonym_type):
            if not replace:
                # add to existing list
                synonym_list = synonym_list_record.synonym_list + synonym_list
            synonym_list_record.synonym_list = list(set(synonym_list))  # remove dupes
            synonym_list_record.last_update_date = datetime.now(UTC)
            db.session.add(synonym_list_record)
        else:
            db.session.add(
                SolrSynonymList(synonym=synonym, synonym_list=synonym_list, synonym_type=synonym_type.value)
            )


    @staticmethod
    def create_or_replace_all(synonyms: dict[str, list[str]], synonym_type: SolrSynonymList.Type) -> list[str]:
        """Bulk update/insert without requiring a DB unique constraint."""
        synonyms_updated = []

        # Load existing synonyms for this type
        existing = SolrSynonymList.find_all_by_synonym_type(synonym_type)
        existing_map = {s.synonym.lower(): s for s in existing}

        for main_synonym, synonym_list in synonyms.items():
            cleaned_list = [syn.strip() for syn in synonym_list if syn and syn != main_synonym]

            # Update existing or add new
            if main_synonym.lower() in existing_map:
                obj = existing_map[main_synonym.lower()]
                obj.synonym_list = list(set(obj.synonym_list + cleaned_list))
                obj.last_update_date = datetime.now(UTC)
            else:
                db.session.add(SolrSynonymList(
                    synonym=main_synonym.lower(),
                    synonym_list=cleaned_list,
                    synonym_type=synonym_type.value,
                    last_update_date=datetime.now(UTC)
                ))

            # Also handle list synonyms
            for list_synonym in cleaned_list:
                if list_synonym.lower() in existing_map:
                    obj = existing_map[list_synonym.lower()]
                    obj.synonym_list = list(set(obj.synonym_list + [main_synonym] + cleaned_list))
                    obj.last_update_date = datetime.now(UTC)
                else:
                    db.session.add(SolrSynonymList(
                        synonym=list_synonym.lower(),
                        synonym_list=[main_synonym, *cleaned_list],
                        synonym_type=synonym_type.value,
                        last_update_date=datetime.now(UTC)
                    ))

            synonyms_updated += [main_synonym, *cleaned_list]

        db.session.commit()
        return synonyms_updated


    @staticmethod
    def delete_all(synonym_type: Type, preserved_synonyms: list[str] | None = None):
        """Delete all synonyms the synonym type."""
        syns_to_delete = SolrSynonymList.find_all_excluding(preserved_synonyms or [], synonym_type)
        for syn in syns_to_delete:
            db.session.delete(syn)
        db.session.commit()
